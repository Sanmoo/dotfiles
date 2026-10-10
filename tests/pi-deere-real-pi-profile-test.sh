#!/usr/bin/env bash
# tier: slow
# The second profile keeps its own credentials: the first account's login never
# reaches it, the second profile's store is never rewritten behind its back, and
# the isolation extension snapshots settings into the second profile only.

# shellcheck disable=SC2154 # the harness assigns the fixture and the globals every case uses
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/pi-deere-real-pi-harness.sh"

test_isolation_extension_snapshots_into_the_second_profile_only() {
	build_fixture
	write_copilot_login
	local before release
	before="$(digest "$SRC/settings.json")"
	release="$tmproot/snapshot-observed"
	# The extension's snapshot exists only while the instance runs (it is removed
	# at shutdown), so keep stdin open and observe it from outside. The window
	# covers a cold launch — the `pi` wrapper resolves its runtime and package
	# before the session starts — and closes when the observer has made its
	# assertions, which is what releases the launch into its clean shutdown. The
	# producer outlasts the observer so that a window that never opens is reported
	# by the observer's assertion, not by a silent EOF.
	(
		cd "$PROJ_A" && env -i PATH="$PATH" HOME="$HOST_HOME" PI_OFFLINE=1 PI_SKIP_VERSION_CHECK=1 \
			"${DEERE_ENV[@]}" bash "$LAUNCHER" --mode rpc < <(rpc '{"id":"1","type":"get_state"}'; wait_for 150 test -e "$release")
	) >"$OUT" 2>"$ERR" &
	local pid=$! seen=0 _attempt
	for _attempt in $(seq 1 75); do
		if [[ -e "$PROF/settings.json.bak" ]]; then
			seen=1
			break
		fi
		sleep 0.2
	done
	[[ "$seen" -eq 1 ]] || {
		kill "$pid" 2>/dev/null || true
		fail "the isolation snapshot belongs in the second profile"
	}
	pass
	[[ ! -e "$SRC/settings.json.bak" ]] || fail "the original profile must not get a snapshot from pi-deere"
	pass
	: >"$release"
	wait "$pid" || true
	assert_eq "$before" "$(digest "$SRC/settings.json")" "original settings unchanged"
}


test_inherited_copilot_token_never_becomes_the_second_account() {
	build_fixture


	# No Copilot login in the second profile; the first account's token is inherited
	# and its login is present in the original profile's auth.json.
	run_in "$PROJ_A" "${DEERE_ENV[@]}" COPILOT_GITHUB_TOKEN=first-account-fake -- bash "$LAUNCHER" --mode rpc < <(rpc '{"id":"1","type":"get_available_models"}')
	assert_out_lacks '"provider":"github-copilot"' "no Copilot model from the inherited token or the first login"
	grep -Fq "FIRST-ACCOUNT-FIXTURE-LOGIN" "$PROF/auth.json" "$OUT" && fail "the first account login must never reach the second profile" || pass
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
	grep -Fq "FIRST-ACCOUNT-FIXTURE-LOGIN" "$PROF/auth.json" && fail "the first account login must not be imported" || pass
	grep -Fq '"github-copilot"' "$PROF/auth.json" || fail "the second account login must remain in its profile"
	pass

	# Logout in the second profile, then a renewal simulated by a new token: neither
	# may touch the original profile's credential store.
	local first_account_before
	first_account_before="$(digest "$SRC/auth.json")"
	printf '{}\n' >"$PROF/auth.json"
	run_in "$PROJ_A" "${DEERE_ENV[@]}" -- bash "$LAUNCHER" --mode rpc < <(rpc '{"id":"1","type":"get_state"}')
	assert_eq "$first_account_before" "$(digest "$SRC/auth.json")" "logout in the second profile leaves the original store alone"
	write_copilot_login
	printf '{"github-copilot":{"type":"oauth","access":"RENEWED-SECOND-TOKEN","refresh":"fake-refresh","expires":9999999999999,"availableModelIds":["gpt-5.6-sol"]}}\n' >"$PROF/auth.json"
	run_in "$PROJ_A" "${DEERE_ENV[@]}" -- bash "$LAUNCHER" --mode rpc < <(rpc '{"id":"1","type":"get_state"}')
	assert_eq "$first_account_before" "$(digest "$SRC/auth.json")" "a renewed second-profile token leaves the original store alone"
	grep -Fq "RENEWED-SECOND-TOKEN" "$PROF/auth.json" || fail "the renewed token stays in the second profile"
	pass
}


pi_deere_run_tests
