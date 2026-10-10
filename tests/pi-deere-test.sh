#!/usr/bin/env bash
# Contract tests for the pi-deere launcher at its process boundary.
#
# The launcher's collaborator is the `pi` executable. This harness puts a stub
# `pi` first on PATH, runs the real launcher in a temporary HOME with a fake
# original agent directory, and asserts on what the stub received (argv, cwd,
# environment), the exit status and signal behaviour, and the profile directory
# the launcher prepared. No network, no real credentials, no real Pi.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$repo_root/pi/.local/bin/pi-deere"

tmproot="$(mktemp -d)"
trap 'rm -rf "$tmproot"' EXIT

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

pass_count=0
pass() {
	pass_count=$((pass_count + 1))
}

assert_eq() {
	local expected="$1" actual="$2" label="$3"
	[[ "$expected" == "$actual" ]] || fail "$label: expected [$expected], got [$actual]"
	pass
}

assert_contains() {
	local haystack="$1" needle="$2" label="$3"
	[[ "$haystack" == *"$needle"* ]] || fail "$label: missing [$needle] in [$haystack]"
	pass
}

assert_not_contains() {
	local haystack="$1" needle="$2" label="$3"
	[[ "$haystack" != *"$needle"* ]] || fail "$label: unexpected [$needle] in [$haystack]"
	pass
}

# Exact-line match, so `arg=` does not match `arg=--models`.
assert_line() {
	local haystack="$1" line="$2" label="$3"
	grep -Fxq -- "$line" <<<"$haystack" || fail "$label: no line [$line]"
	pass
}

digest() {
	cksum <"$1" | cut -d' ' -f1,2
}

# Per-case state. new_case builds a fresh original agent dir, profile location,
# and stub bin directory; each test then launches through run_launcher.
case_root=""
SRC=""
PROF=""
STUB_BIN=""
STUB_LOG=""
LAUNCH_STATUS=0
LAUNCH_STDERR=""

new_case() {
	case_root="$(mktemp -d "$tmproot/case.XXXXXX")"
	SRC="$case_root/home/.pi/agent"
	PROF="$case_root/home/.pi-deere/agent"
	STUB_BIN="$case_root/bin"
	STUB_LOG="$case_root/stub.log"
	mkdir -p "$SRC/extensions" "$SRC/prompts" "$SRC/npm/node_modules" "$STUB_BIN" "$case_root/work"
	printf '{"defaultProvider":"bifrost","defaultModel":"x/y"}\n' >"$SRC/settings.json"
	printf 'shared agents notes\n' >"$SRC/AGENTS.md"
	printf '{"github-copilot":{"type":"oauth","access":"ORIGINAL-TOKEN"}}\n' >"$SRC/auth.json"
	printf 'fixture extension\n' >"$SRC/extensions/fixture.ts"
	printf 'fixture prompt\n' >"$SRC/prompts/fixture.md"
	: >"$STUB_LOG"
	write_stub_pi
}

# The stub records what the launcher handed to Pi. Behaviour is steered by
# FAKE_PI_STATUS, FAKE_PI_SIGNAL, and FAKE_AUTH (ready|not_ready).
write_stub_pi() {
	cat >"$STUB_BIN/pi" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
log="${STUB_LOG:?}"
if [[ "${1:-}" == "auth" && "${2:-}" == "check" ]]; then
	printf 'auth-check %s\n' "$*" >>"$log"
	if [[ "${FAKE_AUTH:-ready}" == "ready" ]]; then
		printf '{"status":"ready","provider":"github-copilot","authType":"oauth"}\n'
		exit 0
	fi
	printf '{"status":"not_ready","provider":"github-copilot","reason":"credentials_not_configured"}\n'
	exit 1
fi
{
	printf 'invoked\n'
	printf 'cwd=%s\n' "$PWD"
	printf 'PI_CODING_AGENT_DIR=%s\n' "${PI_CODING_AGENT_DIR-unset}"
	printf 'PI_CODING_AGENT_SESSION_DIR=%s\n' "${PI_CODING_AGENT_SESSION_DIR-unset}"
	if [[ -n "${COPILOT_GITHUB_TOKEN+x}" ]]; then
		printf 'COPILOT_GITHUB_TOKEN=present\n'
	else
		printf 'COPILOT_GITHUB_TOKEN=absent\n'
	fi
	printf 'argc=%d\n' "$#"
	for arg in "$@"; do
		printf 'arg=%s\n' "$arg"
	done
} >>"$log"
if [[ -n "${FAKE_PI_SIGNAL:-}" ]]; then
	kill -s "$FAKE_PI_SIGNAL" "$$"
	sleep 5
fi
exit "${FAKE_PI_STATUS:-0}"
STUB
	chmod +x "$STUB_BIN/pi"
}

# run_launcher [env assignments...] -- [launcher args...]
# Runs the real launcher from the case work directory with a clean environment
# that only carries what the test sets. Exit status and stderr are captured.
run_launcher() {
	local -a env_args=()
	while [[ $# -gt 0 && "$1" != "--" ]]; do
		env_args+=("$1")
		shift
	done
	[[ "${1:-}" == "--" ]] && shift
	local err="$case_root/stderr.log"
	set +e
	(
		cd "$case_root/work"
		env -i PATH="$STUB_BIN:/usr/bin:/bin" HOME="$case_root/home" \
			STUB_LOG="$STUB_LOG" \
			PI_CODING_AGENT_DIR="$SRC" \
			PI_DEERE_AGENT_DIR="$PROF" \
			${env_args[@]+"${env_args[@]}"} \
			bash "$SCRIPT" "$@"
	) >"$case_root/stdout.log" 2>"$err"
	LAUNCH_STATUS=$?
	set -e
	LAUNCH_STDERR="$(cat "$err")"
}

stub_log() {
	cat "$STUB_LOG"
}

# --- Cases ------------------------------------------------------------------

test_first_launch_prepares_private_profile_with_shared_links() {
	new_case
	run_launcher -- "hello"
	assert_eq 0 "$LAUNCH_STATUS" "first launch status"
	assert_eq "$SRC/extensions" "$(readlink "$PROF/extensions")" "extensions link target"
	assert_eq "$SRC/prompts" "$(readlink "$PROF/prompts")" "prompts link target"
	[[ ! -L "$PROF/settings.json" && -f "$PROF/settings.json" ]] || fail "settings.json must be a copy, not a link"
	pass
	assert_eq "$(cat "$SRC/settings.json")" "$(cat "$PROF/settings.json")" "settings copy matches the shared preferences"
	assert_eq "$SRC/AGENTS.md" "$(readlink "$PROF/AGENTS.md")" "AGENTS.md link target"
	[[ ! -e "$PROF/themes" && ! -L "$PROF/themes" ]] || fail "absent source entry must not be linked"
	pass
	[[ ! -L "$PROF/auth.json" && ! -e "$PROF/auth.json" ]] || fail "launch must not create or link auth.json"
	pass
	if stat -c %a "$PROF" >/dev/null 2>&1; then
		assert_eq 700 "$(stat -c %a "$PROF")" "profile permissions"
	else
		assert_eq 700 "$(stat -f %Lp "$PROF")" "profile permissions"
	fi
}

test_profile_writes_to_settings_never_reach_the_original() {
	new_case
	run_launcher -- "x"
	local before after
	before="$(digest "$SRC/settings.json")"
	printf '{"defaultProvider":"github-copilot"}\n' >"$PROF/settings.json"
	after="$(digest "$SRC/settings.json")"
	assert_eq "$before" "$after" "original settings untouched by a profile write"
	run_launcher -- "again"
	assert_eq "$(cat "$SRC/settings.json")" "$(cat "$PROF/settings.json")" "copy regenerated from the shared preferences"
}

test_source_settings_change_is_seen_on_next_launch() {
	new_case
	run_launcher -- "first"
	printf '{"defaultThinkingLevel":"low"}\n' >"$SRC/settings.json"
	run_launcher -- "second"
	assert_eq 0 "$LAUNCH_STATUS" "status after a shared settings change"
	assert_eq '{"defaultThinkingLevel":"low"}' "$(cat "$PROF/settings.json")" "shared settings change reflected"
}

test_legacy_settings_link_is_replaced_by_a_copy() {
	new_case
	mkdir -p "$PROF"
	ln -s "$SRC/settings.json" "$PROF/settings.json"
	run_launcher -- "x"
	assert_eq 0 "$LAUNCH_STATUS" "status with a legacy settings link"
	[[ ! -L "$PROF/settings.json" ]] || fail "the legacy link must be replaced by a copy"
	pass
	before="$(digest "$SRC/settings.json")"
	printf 'profile only\n' >"$PROF/settings.json"
	assert_eq "$before" "$(digest "$SRC/settings.json")" "original settings untouched after the legacy link is gone"
}

test_pi_subcommands_are_dispatched_without_a_scope() {
	new_case
	run_launcher -- update --extension npm:pi-subagents
	local log
	log="$(stub_log)"
	assert_line "$log" "argc=3" "subcommand arguments untouched"
	assert_not_contains "$log" "github-copilot/*" "no scope added to a subcommand"
	assert_line "$log" "arg=update" "subcommand kept first"

	run_launcher -- auth check --provider github-copilot --json
	assert_not_contains "$(stub_log)" "github-copilot/*" "auth check gets no scope"
}

test_home_tilde_in_profile_dir_is_expanded() {
	new_case
	run_launcher PI_DEERE_AGENT_DIR='~/.pi-deere/agent' -- "x"
	assert_eq 0 "$LAUNCH_STATUS" "status with a tilde profile dir"
	assert_contains "$(stub_log)" "PI_CODING_AGENT_DIR=$PROF" "pi receives the expanded profile dir"
}

test_repeated_launch_is_idempotent() {
	new_case
	run_launcher -- "one"
	assert_eq 0 "$LAUNCH_STATUS" "first status"
	local before after
	before="$(cd "$case_root/home" && find .pi-deere -print | sort && find .pi-deere -type l -exec readlink {} \; | sort)"
	run_launcher -- "two"
	assert_eq 0 "$LAUNCH_STATUS" "second status"
	after="$(cd "$case_root/home" && find .pi-deere -print | sort && find .pi-deere -type l -exec readlink {} \; | sort)"
	assert_eq "$before" "$after" "profile tree after repeated launch"
}

test_arguments_cwd_and_prompt_with_spaces_are_forwarded() {
	new_case
	run_launcher -- --no-session "hello  two words" "" -- --literal-after-separator
	assert_eq 0 "$LAUNCH_STATUS" "status"
	local log
	log="$(stub_log)"
	assert_contains "$log" "cwd=$(cd "$case_root/work" && pwd -P)" "cwd preserved"
	assert_line "$log" "argc=7" "argc with injected scope"
	assert_line "$log" "arg=--models" "injected models flag"
	assert_line "$log" "arg=github-copilot/*" "injected copilot scope"
	assert_line "$log" "arg=--no-session" "native option forwarded"
	assert_line "$log" "arg=hello  two words" "prompt with spaces kept as one argument"
	assert_line "$log" "arg=" "empty argument kept"
	assert_line "$log" "arg=--" "separator forwarded"
	assert_line "$log" "arg=--literal-after-separator" "argument after -- kept"
}

test_caller_models_option_replaces_default_scope() {
	new_case
	run_launcher -- --models "anthropic/*" "hi"
	local log
	log="$(stub_log)"
	assert_contains "$log" "argc=3" "no injected flag when caller sets models"
	assert_not_contains "$log" "github-copilot/*" "default scope suppressed"
}

test_profile_and_session_environment() {
	new_case
	run_launcher -- "x"
	local log
	log="$(stub_log)"
	assert_contains "$log" "PI_CODING_AGENT_DIR=$PROF" "pi receives the profile dir"
	# No session-dir override: a flat override would bypass Pi's per-project grouping.
	assert_contains "$log" "PI_CODING_AGENT_SESSION_DIR=unset" "no session-dir override exported"
}

test_sessions_link_keeps_native_per_project_grouping() {
	new_case
	mkdir -p "$SRC/sessions/--project--"
	printf 'history\n' >"$SRC/sessions/--project--/history.jsonl"
	run_launcher -- "x"
	assert_eq "$SRC/sessions" "$(readlink "$PROF/sessions")" "sessions linked to the original store"
	assert_eq "history" "$(cat "$PROF/sessions/--project--/history.jsonl")" "existing grouped history visible"
}

test_missing_source_sessions_dir_is_created_for_the_link() {
	new_case
	rm -rf "$SRC/sessions"
	run_launcher -- "x"
	assert_eq 0 "$LAUNCH_STATUS" "status without sessions dir"
	assert_eq "$SRC/sessions" "$(readlink "$PROF/sessions")" "sessions link created"
	[[ -d "$SRC/sessions" ]] || fail "source sessions dir should exist after launch"
	pass
}

test_explicit_session_dir_is_respected() {
	new_case
	run_launcher PI_CODING_AGENT_SESSION_DIR="$case_root/elsewhere" -- "x"
	assert_contains "$(stub_log)" "PI_CODING_AGENT_SESSION_DIR=$case_root/elsewhere" "caller session dir wins"
}

test_inherited_copilot_token_is_not_forwarded() {
	new_case
	run_launcher COPILOT_GITHUB_TOKEN=first-account-token -- "x"
	local log
	log="$(stub_log)"
	assert_contains "$log" "COPILOT_GITHUB_TOKEN=absent" "inherited token removed before pi starts"
	assert_not_contains "$LAUNCH_STDERR" "first-account-token" "token never printed"
}

test_exit_status_is_pis_status() {
	new_case
	run_launcher FAKE_PI_STATUS=7 -- "x"
	assert_eq 7 "$LAUNCH_STATUS" "exit status propagated"
}

test_signal_terminates_with_pis_signal() {
	new_case
	run_launcher FAKE_PI_SIGNAL=TERM -- "x"
	assert_eq 143 "$LAUNCH_STATUS" "SIGTERM status propagated"
}

test_missing_copilot_login_warns_but_starts_pi() {
	new_case
	run_launcher FAKE_AUTH=not_ready -- "x"
	assert_eq 0 "$LAUNCH_STATUS" "pi still starts so /login is available"
	assert_contains "$LAUNCH_STDERR" "GitHub Copilot is not logged in for this profile" "actionable login warning"
	assert_contains "$LAUNCH_STDERR" "/login" "login instruction"
	assert_contains "$(stub_log)" "invoked" "pi was started"
}

test_ready_login_prints_no_warning() {
	new_case
	run_launcher -- "x"
	assert_eq "" "$LAUNCH_STDERR" "no warning when logged in"
	assert_contains "$(stub_log)" "auth-check auth check --provider github-copilot --json" "auth status checked for copilot"
}

test_credentials_stay_separate_from_original() {
	new_case
	run_launcher -- "x"
	printf '{"github-copilot":{"type":"oauth","access":"SECOND-TOKEN"}}\n' >"$PROF/auth.json"
	chmod 600 "$PROF/auth.json"
	local source_before source_after
	source_before="$(digest "$SRC/auth.json")"
	run_launcher -- "again"
	source_after="$(digest "$SRC/auth.json")"
	assert_eq "$source_before" "$source_after" "original auth.json untouched by the second profile"
	[[ ! -L "$PROF/auth.json" ]] || fail "profile auth.json must be a regular file"
	pass
	assert_contains "$(cat "$PROF/auth.json")" "SECOND-TOKEN" "profile keeps its own credential"
}

test_original_settings_are_not_rewritten() {
	new_case
	local before after
	before="$(digest "$SRC/settings.json")"
	run_launcher -- "x"
	after="$(digest "$SRC/settings.json")"
	assert_eq "$before" "$after" "original settings.json unchanged"
	[[ ! -e "$SRC/settings.json.bak" ]] || fail "launch must not create backups in the original"
	pass
}

test_regular_file_conflict_fails_without_changes() {
	new_case
	mkdir -p "$PROF"
	printf 'user file\n' >"$PROF/extensions"
	run_launcher -- "x"
	assert_eq 1 "$LAUNCH_STATUS" "conflict status"
	assert_contains "$LAUNCH_STDERR" "conflict" "actionable conflict message"
	assert_eq "user file" "$(cat "$PROF/extensions")" "conflicting file kept"
	[[ ! -L "$PROF/settings.json" ]] || fail "no shared link may be created after a conflict"
	pass
	[[ "$(stub_log)" == "" ]] || fail "pi must not start after a conflict"
	pass
}

test_foreign_link_conflict_fails_without_changes() {
	new_case
	mkdir -p "$PROF" "$case_root/other"
	ln -s "$case_root/other" "$PROF/prompts"
	run_launcher -- "x"
	assert_eq 1 "$LAUNCH_STATUS" "foreign link status"
	assert_contains "$LAUNCH_STDERR" "conflict" "foreign link reported"
	assert_eq "$case_root/other" "$(readlink "$PROF/prompts")" "foreign link kept"
}

test_auth_json_link_is_refused() {
	new_case
	mkdir -p "$PROF"
	ln -s "$SRC/auth.json" "$PROF/auth.json"
	run_launcher -- "x"
	assert_eq 1 "$LAUNCH_STATUS" "auth link status"
	assert_contains "$LAUNCH_STDERR" "auth.json is a link" "credential link refused"
	assert_eq "$SRC/auth.json" "$(readlink "$PROF/auth.json")" "auth link kept"
}

test_missing_original_agent_dir_fails() {
	new_case
	rm -rf "$SRC"
	run_launcher -- "x"
	assert_eq 1 "$LAUNCH_STATUS" "missing source status"
	assert_contains "$LAUNCH_STDERR" "agent directory of the original Pi not found" "actionable source message"
}

test_missing_settings_fails() {
	new_case
	rm -f "$SRC/settings.json"
	run_launcher -- "x"
	assert_eq 1 "$LAUNCH_STATUS" "missing settings status"
	assert_contains "$LAUNCH_STDERR" "missing" "missing settings message"
}

test_missing_pi_executable_fails() {
	new_case
	rm -f "$STUB_BIN/pi"
	run_launcher -- "x"
	assert_eq 127 "$LAUNCH_STATUS" "missing pi status"
	assert_contains "$LAUNCH_STDERR" "pi executable was not found" "missing executable message"
}

test_stale_profile_link_to_a_removed_entry_is_pruned() {
	new_case
	run_launcher -- "first"
	assert_eq "$SRC/prompts" "$(readlink "$PROF/prompts")" "prompts linked before the removal"
	rm -rf "$SRC/prompts"
	run_launcher -- "second"
	assert_eq 0 "$LAUNCH_STATUS" "launch after the original entry was removed"
	[[ ! -e "$PROF/prompts" && ! -L "$PROF/prompts" ]] || fail "the stale link pi-deere made must be pruned"
	pass
}

test_foreign_link_to_a_missing_target_is_left_alone() {
	new_case
	mkdir -p "$PROF"
	ln -s "$case_root/elsewhere-missing" "$PROF/themes"
	run_launcher -- "x"
	assert_eq 0 "$LAUNCH_STATUS" "launch with a foreign dangling link"
	assert_eq "$case_root/elsewhere-missing" "$(readlink "$PROF/themes")" "foreign link kept, not pruned"
}

test_broken_shared_link_fails() {
	new_case
	ln -s "$case_root/missing-target.md" "$SRC/themes"
	run_launcher -- "x"
	assert_eq 1 "$LAUNCH_STATUS" "broken source status"
	assert_contains "$LAUNCH_STDERR" "broken link" "broken shared resource detected"
	assert_contains "$LAUNCH_STDERR" "$case_root/missing-target.md" "error names the broken target"
	assert_contains "$LAUNCH_STDERR" "rm '$SRC/themes'" "error says which link to remove"
}

test_entry_added_to_source_is_shared_on_next_launch() {
	new_case
	run_launcher -- "first"
	mkdir -p "$SRC/themes"
	printf '{}\n' >"$SRC/themes/dark.json"
	run_launcher -- "second"
	assert_eq 0 "$LAUNCH_STATUS" "status after source change"
	assert_eq "$SRC/themes" "$(readlink "$PROF/themes")" "new source theme linked"
}

test_same_directory_is_refused() {
	new_case
	run_launcher PI_DEERE_AGENT_DIR="$SRC" -- "x"
	assert_eq 1 "$LAUNCH_STATUS" "same dir status"
	assert_contains "$LAUNCH_STDERR" "must differ" "same dir refused"
}

for test_name in $(declare -F | awk '{print $3}' | grep '^test_'); do
	"$test_name"
	printf 'ok %s\n' "$test_name"
done

printf 'pi-deere launcher contract: %d assertions passed\n' "$pass_count"
