#!/usr/bin/env bash
# tier: slow
# What a launch loads and what a session starts with: the resources shared with
# the original profile, and the provider, model and thinking level a session
# resolves to.

# shellcheck disable=SC2154 # the harness assigns the fixture and the globals every case uses
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/pi-deere-real-pi-harness.sh"

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


test_thinking_level_is_restored_from_the_session() {
	build_fixture
	write_copilot_login
	# A Copilot session that was recorded at a low thinking level; the default is high.
	make_session "$PROJ_A" "0195a0f5-0000-7000-8000-00000000d001" "2026-10-09T10-08-00-000Z" github-copilot gpt-5.6-sol "marker-D1" low
	run_in "$PROJ_A" "${DEERE_ENV[@]}" -- bash "$LAUNCHER" --mode rpc --session 0195a0f5-0000-7000-8000-00000000d001 < <(rpc '{"id":"1","type":"get_state"}')
	assert_eq 0 "$STATUS" "thinking session status"
	assert_out_has '"thinkingLevel":"low"' "the session's thinking level is restored, not the default"
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


pi_deere_run_tests
