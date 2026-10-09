#!/usr/bin/env bash
# tier: slow
# Hermetic integration of pi-deere with the real Pi executable.
#
# Unlike tests/pi-deere-test.sh, nothing here is stubbed: the real `pi` loads the
# resources the launcher prepared, reads and writes the shared session store,
# and reports its model choices over the RPC protocol. The fixture is a
# temporary home with a self-contained model catalog and fake credentials, and
# Pi runs offline (PI_OFFLINE=1), so there is no network, no GitHub login, and
# no request is sent to any model provider.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$repo_root/pi/.local/bin/pi-deere"
ISOLATION_EXTENSION="$repo_root/pi/.pi/agent/extensions/session-model-isolation.ts"

command -v pi >/dev/null 2>&1 || {
	printf 'FAIL: the real pi executable must be on PATH for this test\n' >&2
	exit 1
}

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

# --- Fixture ------------------------------------------------------------------

ID_A1="0195a0f1-0000-7000-8000-00000000a001" # project A, older, copilot model
ID_A2="0195a0f2-0000-7000-8000-00000000a002" # project A, newer, copilot model
ID_B1="0195a0f3-0000-7000-8000-00000000b001" # project B only
ID_C1="0195a0f4-0000-7000-8000-00000000c001" # project A, anthropic model

HOME_DIR=""
SRC=""
PROF=""
DEERE_ENV=()
PROJ_A=""
PROJ_B=""
OUT=""
ERR=""
STATUS=0

# Session files are grouped by working directory, as Pi's default layout does:
# sessions/--<cwd without leading slash, / \ : replaced by ->--/<stamp>_<id>.jsonl
make_session() {
	local cwd="$1" id="$2" stamp="$3" provider="$4" model="$5" text="$6"
	local enc="${cwd#/}"
	enc="${enc//\//-}"
	enc="${enc//:/-}"
	local dir="$SRC/sessions/--$enc--"
	mkdir -p "$dir"
	local file="$dir/${stamp}_${id}.jsonl"
	printf '{"type":"session","version":3,"id":"%s","timestamp":"2026-10-09T10:00:00.000Z","cwd":"%s"}\n' "$id" "$cwd" >"$file"
	printf '{"type":"model_change","id":"m%s","parentId":null,"timestamp":"2026-10-09T10:00:01.000Z","provider":"%s","modelId":"%s"}\n' "${id:0:8}" "$provider" "$model" >>"$file"
	printf '{"type":"message","id":"u%s","parentId":"m%s","timestamp":"2026-10-09T10:00:02.000Z","message":{"role":"user","content":"%s","timestamp":1733234402000}}\n' "${id:0:8}" "${id:0:8}" "$text" >>"$file"
}

build_fixture() {
	local root
	root="$(cd "$(mktemp -d "$tmproot/fixture.XXXXXX")" && pwd -P)"
	HOME_DIR="$root/home"
	SRC="$HOME_DIR/.pi/agent"
	PROF="$HOME_DIR/.pi-deere/agent"
	PROJ_A="$root/projA"
	PROJ_B="$root/projB"
	OUT="$root/out.log"
	ERR="$root/err.log"
	mkdir -p "$SRC/extensions" "$SRC/prompts" "$SRC/skills/deere-skill" \
		"$SRC/npm/node_modules/deere-fixture-pkg" "$SRC/npm/node_modules/deere-fixture-dep" \
		"$PROJ_A" "$PROJ_B"

	# Shared preferences: the original default is not Copilot.
	cat >"$SRC/settings.json" <<'JSON'
{
  "defaultProvider": "anthropic",
  "defaultModel": "claude-sonnet-5.5",
  "defaultThinkingLevel": "high",
  "packages": ["npm:deere-fixture-pkg"]
}
JSON

	# Self-contained model catalog (what models-store.json caches offline).
	cat >"$SRC/models-store.json" <<'JSON'
{
  "github-copilot": {
    "checkedAt": "2026-01-01T00:00:00.000Z",
    "etag": null,
    "lastModified": null,
    "models": [
      {"id":"gpt-5.6-sol","name":"GPT 5.6 Sol","api":"openai-responses","provider":"github-copilot","baseUrl":"https://api.individual.githubcopilot.com","reasoning":true,"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":1000000,"maxTokens":128000,"type":"chat"},
      {"id":"claude-sonnet-5.5","name":"Claude Sonnet 5.5","api":"anthropic-messages","provider":"github-copilot","baseUrl":"https://api.individual.githubcopilot.com","reasoning":true,"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":1000000,"maxTokens":128000,"type":"chat"}
    ]
  },
  "anthropic": {
    "checkedAt": "2026-01-01T00:00:00.000Z",
    "etag": null,
    "lastModified": null,
    "models": [
      {"id":"claude-sonnet-5.5","name":"Claude Sonnet 5.5","api":"anthropic-messages","provider":"anthropic","baseUrl":"https://api.anthropic.com","reasoning":true,"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":200000,"maxTokens":64000,"type":"chat"}
    ]
  }
}
JSON

	# Shared resources: an extension, a prompt template, a skill, the real
	# isolation extension, and an npm package with a local dependency.
	cat >"$SRC/extensions/deere-ext.ts" <<'TS'
export default function (pi) {
	pi.registerCommand("deere-ext-cmd", { description: "fixture extension", handler: async () => {} });
}
TS
	cp "$ISOLATION_EXTENSION" "$SRC/extensions/session-model-isolation.ts"
	printf 'Fixture prompt body\n' >"$SRC/prompts/deere-prompt.md"
	printf -- '---\nname: deere-skill\ndescription: fixture skill\n---\nFixture skill body\n' >"$SRC/skills/deere-skill/SKILL.md"
	printf '{"name":"deere-fixture-dep","version":"1.0.0","main":"index.js"}\n' >"$SRC/npm/node_modules/deere-fixture-dep/package.json"
	printf 'module.exports.value = "dep-ok";\n' >"$SRC/npm/node_modules/deere-fixture-dep/index.js"
	printf '{"name":"deere-fixture-pkg","version":"1.0.0","pi":{"extensions":["./index.js"]},"dependencies":{"deere-fixture-dep":"1.0.0"}}\n' >"$SRC/npm/node_modules/deere-fixture-pkg/package.json"
	cat >"$SRC/npm/node_modules/deere-fixture-pkg/index.js" <<'JS'
const dep = require("deere-fixture-dep");
module.exports = function (pi) {
	pi.registerCommand("deere-pkg-cmd", { description: "pkg " + dep.value, handler: async () => {} });
};
JS

	# The original profile holds an Anthropic key that the second profile must not import.
	printf '{"anthropic":{"type":"api_key","key":"ORIGINAL-FIXTURE-KEY"}}\n' >"$SRC/auth.json"
	chmod 600 "$SRC/auth.json"

	make_session "$PROJ_A" "$ID_A1" "2026-10-09T10-00-00-000Z" github-copilot gpt-5.6-sol "marker-A1"
	sleep 1
	make_session "$PROJ_A" "$ID_A2" "2026-10-09T10-05-00-000Z" github-copilot gpt-5.6-sol "marker-A2"
	make_session "$PROJ_B" "$ID_B1" "2026-10-09T10-06-00-000Z" github-copilot gpt-5.6-sol "marker-B1"
	make_session "$PROJ_A" "$ID_C1" "2026-10-09T10-07-00-000Z" anthropic claude-sonnet-5.5 "marker-C1"
	DEERE_ENV=(PI_CODING_AGENT_DIR="$SRC" PI_DEERE_AGENT_DIR="$PROF")
}

# The second account's login, as /login would have written it. Fake values only.
write_copilot_login() {
	local expires=$(($(date +%s) * 1000 + 999999999999))
	mkdir -p "$PROF"
	printf '{"github-copilot":{"type":"oauth","access":"fake-access","refresh":"fake-refresh","expires":%s,"availableModelIds":["gpt-5.6-sol","claude-sonnet-5.5"]}}\n' "$expires" >"$PROF/auth.json"
	chmod 600 "$PROF/auth.json"
}

digest() {
	cksum <"$1" | cut -d' ' -f1,2
}

# run_in <cwd> [ENV=VAL ...] -- <command...>
# Runs in a clean environment (only PATH, HOME, and offline flags plus the
# named variables). Stdin is inherited, so callers pass RPC input with
# process substitution. Stdout, stderr, and the status are kept in globals.
run_in() {
	local cwd="$1"
	shift
	local -a extra=()
	while [[ $# -gt 0 && "$1" != "--" ]]; do
		extra+=("$1")
		shift
	done
	shift
	set +e
	(
		cd "$cwd" && env -i PATH="$PATH" HOME="$HOME_DIR" PI_OFFLINE=1 PI_SKIP_VERSION_CHECK=1 \
			${extra[@]+"${extra[@]}"} "$@"
	) >"$OUT" 2>"$ERR"
	STATUS=$?
	set -e
}

# rpc <json>... prints one RPC command per line.
rpc() {
	printf '%s\n' "$@"
}

assert_out_has() {
	grep -Fq -- "$1" "$OUT" || fail "$2: missing [$1] in output: $(head -c 400 "$OUT")"
	pass
}

assert_out_lacks() {
	if grep -Fq -- "$1" "$OUT"; then
		fail "$2: unexpected [$1] in output"
	fi
	pass
}

assert_eq() {
	[[ "$1" == "$2" ]] || fail "$3: expected [$1], got [$2]"
	pass
}

# --- Cases --------------------------------------------------------------------

test_shared_resources_load_through_the_second_profile() {
	build_fixture
	write_copilot_login


	run_in "$PROJ_A" "${DEERE_ENV[@]}" -- bash "$LAUNCHER" --mode rpc < <(rpc '{"id":"1","type":"get_commands"}')
	assert_eq 0 "$STATUS" "pi-deere status"
	assert_out_has '"name":"deere-ext-cmd"' "extension from the shared store"
	assert_out_has '"name":"deere-pkg-cmd"' "npm package with a local dependency"
	assert_out_has '"name":"deere-prompt"' "prompt template from the shared store"
	assert_out_has '"name":"skill:deere-skill"' "skill from the shared store"

	# A change in the common source shows up on the next launch, with no second edit.
	printf 'Late prompt\n' >"$SRC/prompts/deere-late.md"
	run_in "$PROJ_A" "${DEERE_ENV[@]}" -- bash "$LAUNCHER" --mode rpc < <(rpc '{"id":"1","type":"get_commands"}')
	assert_out_has '"name":"deere-late"' "shared change reflected on the next run"
}

test_isolation_extension_snapshots_into_the_second_profile_only() {
	build_fixture
	write_copilot_login
	local before
	before="$(digest "$SRC/settings.json")"
	# The extension's snapshot exists only while the instance runs (it is removed
	# at shutdown), so keep stdin open and observe it from outside.
	(
		cd "$PROJ_A" && env -i PATH="$PATH" HOME="$HOME_DIR" PI_OFFLINE=1 PI_SKIP_VERSION_CHECK=1 \
			"${DEERE_ENV[@]}" bash "$LAUNCHER" --mode rpc < <(rpc '{"id":"1","type":"get_state"}'; sleep 5)
	) >"$OUT" 2>"$ERR" &
	local pid=$! seen=0 _attempt
	for _attempt in $(seq 1 50); do
		if [[ -e "$PROF/settings.json.bak" ]]; then
			seen=1
			break
		fi
		sleep 0.2
	done
	[[ "$seen" -eq 1 ]] || fail "the isolation snapshot belongs in the second profile"
	pass
	[[ ! -e "$SRC/settings.json.bak" ]] || fail "the original profile must not get a snapshot from pi-deere"
	pass
	wait "$pid" || true
	assert_eq "$before" "$(digest "$SRC/settings.json")" "original settings unchanged"
}

test_new_session_uses_copilot_even_when_original_default_is_another_provider() {
	build_fixture
	write_copilot_login


	# An Anthropic key is inherited, so Anthropic is the configured default.
	run_in "$PROJ_A" "${DEERE_ENV[@]}" ANTHROPIC_API_KEY=fake-anthropic -- bash "$LAUNCHER" --mode rpc < <(rpc '{"id":"1","type":"get_state"}')
	assert_out_has '"provider":"github-copilot"' "pi-deere default provider"
	assert_out_lacks '"provider":"anthropic"' "no anthropic model in pi-deere"

	run_in "$PROJ_A" PI_CODING_AGENT_DIR="$SRC" ANTHROPIC_API_KEY=fake-anthropic -- pi --mode rpc < <(rpc '{"id":"1","type":"get_state"}')
	assert_out_has '"provider":"anthropic"' "original pi keeps its default provider"
}

test_exact_session_resume_opens_the_chosen_session() {
	build_fixture
	write_copilot_login
	# First, on the untouched fixture: --continue picks the newest session (C1).
	# Running it before any other launch keeps that ordering independent of mtimes.
	run_in "$PROJ_A" "${DEERE_ENV[@]}" -- bash "$LAUNCHER" --mode rpc --continue < <(rpc '{"id":"1","type":"get_state"}')
	assert_eq 0 "$STATUS" "continue status"
	assert_out_has "\"sessionId\":\"$ID_C1\"" "--continue picks the newest session"

	# Then the exact older session, not the newest one, with its own history.
	run_in "$PROJ_A" "${DEERE_ENV[@]}" -- bash "$LAUNCHER" --mode rpc --session "$ID_A1" < <(rpc '{"id":"1","type":"get_state"}' '{"id":"2","type":"get_messages"}')
	assert_eq 0 "$STATUS" "older session status"
	assert_out_has "\"sessionId\":\"$ID_A1\"" "the chosen older session is opened"
	assert_out_has "marker-A1" "older session history"
	assert_out_lacks "marker-A2" "newer session history absent"
	assert_out_has '"id":"gpt-5.6-sol"' "session model restored when Copilot offers it"

	run_in "$PROJ_A" "${DEERE_ENV[@]}" -- bash "$LAUNCHER" --mode rpc --session "${ID_A2:0:8}" < <(rpc '{"id":"1","type":"get_state"}')
	assert_out_has "\"sessionId\":\"$ID_A2\"" "a unique prefix resolves to its session"
}

test_missing_session_fails_visibly_without_creating_one() {
	build_fixture
	write_copilot_login


	local before after
	before="$(find "$SRC/sessions" -name '*.jsonl' | wc -l)"
	run_in "$PROJ_A" "${DEERE_ENV[@]}" -- bash "$LAUNCHER" --mode rpc --session 0195a0f9-0000-7000-8000-000000000000 < <(rpc '{"id":"1","type":"get_state"}')
	[[ "$STATUS" -ne 0 ]] || fail "a missing session must not exit successfully"
	pass
	grep -Fq "No session found matching" "$ERR" || fail "the missing reference must be reported on stderr"
	pass
	after="$(find "$SRC/sessions" -name '*.jsonl' | wc -l)"
	assert_eq "$before" "$after" "no empty session created"
}

test_sessions_are_scoped_to_their_project() {
	build_fixture
	write_copilot_login


	run_in "$PROJ_B" "${DEERE_ENV[@]}" -- bash "$LAUNCHER" --mode rpc --continue < <(rpc '{"id":"1","type":"get_state"}')
	assert_out_has "\"sessionId\":\"$ID_B1\"" "continue in project B opens its own session"
	assert_out_lacks "\"sessionId\":\"$ID_A2\"" "project A session not offered in project B"

	# A session from another project is offered for fork, never opened silently.
	run_in "$PROJ_A" "${DEERE_ENV[@]}" -- bash "$LAUNCHER" --mode rpc --session "$ID_B1" < <(rpc '{"id":"1","type":"get_state"}')
	assert_out_lacks "\"sessionId\":\"$ID_B1\"" "cross-project session not opened without a fork"
}

test_messages_written_in_the_second_profile_return_to_the_original() {
	build_fixture
	write_copilot_login


	run_in "$PROJ_A" "${DEERE_ENV[@]}" -- bash "$LAUNCHER" --mode rpc --session "$ID_A1" < <(
		rpc '{"id":"1","type":"bash","command":"echo written-from-deere"}'
		sleep 4
	)
	assert_eq 0 "$STATUS" "pi-deere bash status"
	grep -Fq "written-from-deere" "$SRC"/sessions/*/*"$ID_A1".jsonl || fail "the message must persist in the shared session"
	pass

	run_in "$PROJ_A" PI_CODING_AGENT_DIR="$SRC" -- pi --mode rpc --session "$ID_A1" < <(rpc '{"id":"1","type":"get_messages"}')
	assert_out_has "written-from-deere" "the original pi reads the message back"
}

test_inherited_copilot_token_never_becomes_the_second_account() {
	build_fixture


	# No Copilot login in the second profile; the first account's token is inherited.
	run_in "$PROJ_A" "${DEERE_ENV[@]}" COPILOT_GITHUB_TOKEN=first-account-fake -- bash "$LAUNCHER" --mode rpc < <(rpc '{"id":"1","type":"get_available_models"}')
	assert_out_lacks '"provider":"github-copilot"' "no Copilot model from the inherited token"
	grep -Fq "GitHub Copilot is not logged in for this profile" "$ERR" || fail "an actionable login hint is expected"
	pass
	grep -Fq "first-account-fake" "$ERR" "$OUT" && fail "the inherited token must never be printed" || pass
}

test_credentials_stay_private_to_each_profile() {
	build_fixture
	write_copilot_login


	local before
	before="$(digest "$SRC/auth.json")"
	run_in "$PROJ_A" "${DEERE_ENV[@]}" -- bash "$LAUNCHER" --mode rpc < <(rpc '{"id":"1","type":"get_state"}')
	assert_eq "$before" "$(digest "$SRC/auth.json")" "original credentials untouched"
	[[ ! -L "$PROF/auth.json" ]] || fail "the second profile must keep its own credential file"
	pass
	grep -Fq "ORIGINAL-FIXTURE-KEY" "$PROF/auth.json" && fail "the original credential must not be imported" || pass
	grep -Fq '"github-copilot"' "$PROF/auth.json" || fail "the second account login must remain in its profile"
	pass
}

test_unavailable_session_model_is_restored_visibly_on_copilot() {
	build_fixture
	write_copilot_login


	# C1 was recorded with an Anthropic model that this profile cannot use.
	run_in "$PROJ_A" "${DEERE_ENV[@]}" -- bash "$LAUNCHER" --mode rpc --session "$ID_C1" < <(rpc '{"id":"1","type":"get_state"}' '{"id":"2","type":"get_messages"}')
	assert_out_has "\"sessionId\":\"$ID_C1\"" "the exact session is still opened"
	assert_out_has '"provider":"github-copilot"' "the fallback stays inside the second account"
	assert_out_lacks '"provider":"anthropic"' "no provider switch to Anthropic"
}

for test_name in $(declare -F | awk '{print $3}' | grep '^test_'); do
	"$test_name"
	printf 'ok %s\n' "$test_name"
done

printf 'pi-deere real-pi integration: %d assertions passed\n' "$pass_count"
