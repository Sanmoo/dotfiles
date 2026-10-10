# shellcheck shell=bash
# shellcheck disable=SC2034 # the globals declared here are this harness' interface: the sourcing units use them
# Shared harness for the pi-deere real-Pi integration units.
#
# This file is not a test: the gate discovers `tests/*-test.sh`, and the three
# units below it source this harness. They carry the fixture, the RPC helpers and
# the assertions, so each unit owns only its cases while all of them share one
# vocabulary; the units are independent because every case builds its own
# fixture.
#
# The real `pi` loads the resources the launcher prepared, reads and writes the
# shared session store, and reports its model choices over the RPC protocol.
# Unlike tests/pi-deere-test.sh, nothing here is stubbed. The fixture is a
# temporary agent profile with a self-contained model catalog and fake
# credentials, and Pi runs offline (PI_OFFLINE=1), so no request is sent to any
# model provider. HOME stays the real one: the installed `pi` wrapper resolves
# its Node runtime through mise and its package through npm under HOME, so
# pointing HOME at a temporary directory makes every launch install a whole Node
# runtime and re-download the package. The profile is isolated by
# PI_CODING_AGENT_DIR and PI_DEERE_AGENT_DIR instead, which is what the launcher
# and the isolation extension both read.

# and the isolation extension both read.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUNCHER="$repo_root/pi/.local/bin/pi-deere"
ISOLATION_EXTENSION="$repo_root/pi/.pi/agent/extensions/session-model-isolation.ts"
HOST_HOME="$HOME"

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
# An optional 7th argument records a thinking level after the user message.
make_session() {
	local cwd="$1" id="$2" stamp="$3" provider="$4" model="$5" text="$6" thinking="${7:-}"
	local enc="${cwd#/}"
	enc="${enc//\//-}"
	enc="${enc//:/-}"
	local dir="$SRC/sessions/--$enc--"
	mkdir -p "$dir"
	local file="$dir/${stamp}_${id}.jsonl"
	printf '{"type":"session","version":3,"id":"%s","timestamp":"2026-10-09T10:00:00.000Z","cwd":"%s"}\n' "$id" "$cwd" >"$file"
	printf '{"type":"model_change","id":"m%s","parentId":null,"timestamp":"2026-10-09T10:00:01.000Z","provider":"%s","modelId":"%s"}\n' "${id:0:8}" "$provider" "$model" >>"$file"
	printf '{"type":"message","id":"u%s","parentId":"m%s","timestamp":"2026-10-09T10:00:02.000Z","message":{"role":"user","content":"%s","timestamp":1733234402000}}\n' "${id:0:8}" "${id:0:8}" "$text" >>"$file"
	if [[ -n "$thinking" ]]; then
		printf '{"type":"thinking_level_change","id":"t%s","parentId":"u%s","timestamp":"2026-10-09T10:00:03.000Z","thinkingLevel":"%s"}\n' "${id:0:8}" "${id:0:8}" "$thinking" >>"$file"
	fi
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
	# The original profile also holds the first Copilot account's login; the
	# second profile must never see it.
	printf '{"anthropic":{"type":"api_key","key":"ORIGINAL-FIXTURE-KEY"},"github-copilot":{"type":"oauth","access":"FIRST-ACCOUNT-FIXTURE-LOGIN","refresh":"FIRST-ACCOUNT-REFRESH","expires":9999999999999,"availableModelIds":["gpt-5.6-sol"]}}\n' >"$SRC/auth.json"
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
		cd "$cwd" && env -i PATH="$PATH" HOME="$HOST_HOME" PI_OFFLINE=1 PI_SKIP_VERSION_CHECK=1 \
			${extra[@]+"${extra[@]}"} "$@"
	) >"$OUT" 2>"$ERR"
	STATUS=$?
	set -e
}

# rpc <json>... prints one RPC command per line.
rpc() {
	printf '%s\n' "$@"
}

# wait_for <attempts> <command...>
# Polls `command` every 0.2s until it succeeds or the attempt budget is spent,
# and reports whether it succeeded. It is the tail of an RPC stdin producer:
# while it polls, stdin stays open and the launch keeps running; when it
# returns, stdin reaches EOF and the launch shuts down cleanly. A fixed window
# instead either races a cold launch — the command is never read — or is paid in
# full on every run whatever the machine does.
wait_for() {
	local attempts="$1"
	shift
	local _attempt
	for ((_attempt = 0; _attempt < attempts; _attempt++)); do
		if "$@"; then
			return 0
		fi
		sleep 0.2
	done
	return 1
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


# --- Runner -------------------------------------------------------------------

# pi_deere_run_tests runs every test_ function the sourcing file declares, then
# reports the assertion count. Each unit is one gate unit: it owns its cases and
# its fixture, and no unit depends on another having run.
pi_deere_run_tests() {
	local test_name
	for test_name in $(declare -F | awk '{print $3}' | grep '^test_'); do
		"$test_name"
		printf 'ok %s\n' "$test_name"
	done
	printf 'pi-deere real-pi integration: %d assertions passed\n' "$pass_count"
}
