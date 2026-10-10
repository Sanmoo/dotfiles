#!/usr/bin/env bash
# tier: slow
# The session store the two profiles share: exact resume, project scoping,
# missing references, and a message written in the second profile reaching the
# original one.

# shellcheck disable=SC2154 # the harness assigns the fixture and the globals every case uses
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/pi-deere-real-pi-harness.sh"

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


	# The window holds stdin open until the command it carries has been read and
	# its message persisted: the installed `pi` wrapper resolves its runtime and
	# package before the session starts, so a short window races the launch and
	# the command is never read, while a fixed one is paid in full on every run.
	run_in "$PROJ_A" "${DEERE_ENV[@]}" -- bash "$LAUNCHER" --mode rpc --session "$ID_A1" < <(
		rpc '{"id":"1","type":"bash","command":"echo written-from-deere"}'
		wait_for 150 grep -Fq "written-from-deere" "$SRC"/sessions/*/*"$ID_A1".jsonl
	)
	assert_eq 0 "$STATUS" "pi-deere bash status"
	grep -Fq "written-from-deere" "$SRC"/sessions/*/*"$ID_A1".jsonl || fail "the message must persist in the shared session"
	pass

	run_in "$PROJ_A" PI_CODING_AGENT_DIR="$SRC" -- pi --mode rpc --session "$ID_A1" < <(rpc '{"id":"1","type":"get_messages"}')
	assert_out_has "written-from-deere" "the original pi reads the message back"
}


pi_deere_run_tests
