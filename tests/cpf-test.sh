#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/general/bin/cpf"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

validate_cpf() {
	local cpf="$1"
	cpf="${cpf//[^0-9]/}"
	if [[ ${#cpf} -ne 11 ]]; then
		echo "INVALID LENGTH (${#cpf}): $1" >&2
		return 1
	fi

	# First check digit (weights 10→2)
	local sum=0
	for ((i = 0; i < 9; i++)); do
		sum=$((sum + ${cpf:i:1} * (10 - i)))
	done
	local rem=$((sum % 11))
	local d1=$((rem < 2 ? 0 : 11 - rem))

	# Second check digit (weights 11→2)
	sum=0
	for ((i = 0; i < 10; i++)); do
		sum=$((sum + ${cpf:i:1} * (11 - i)))
	done
	rem=$((sum % 11))
	local d2=$((rem < 2 ? 0 : 11 - rem))

	if [[ $d1 -ne ${cpf:9:1} || $d2 -ne ${cpf:10:1} ]]; then
		echo "INVALID CHECK DIGITS (expected ${d1}${d2} got ${cpf:9:2}): $1" >&2
		return 1
	fi
}

# Test: unformatted output produces 11-digit valid CPF
echo -n "Testing unformatted… "
output=$("$SCRIPT")
if [[ ! "$output" =~ ^[0-9]{11}$ ]]; then
	echo "FAIL: expected 11 digits, got: $output"
	exit 1
fi
validate_cpf "$output"
echo "OK"

# Test: formatted output produces valid CPF with mask
echo -n "Testing formatted… "
output=$("$SCRIPT" -f)
if [[ ! "$output" =~ ^[0-9]{3}\.[0-9]{3}\.[0-9]{3}-[0-9]{2}$ ]]; then
	echo "FAIL: expected XXX.XXX.XXX-XX format, got: $output"
	exit 1
fi
validate_cpf "$output"
echo "OK"

# Test: generate 100 random CPFs and validate all
echo -n "Testing 100 random CPFs… "
for _ in $(seq 1 100); do
	output=$("$SCRIPT")
	validate_cpf "$output"
done
echo "OK"
