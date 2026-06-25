#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/general/bin/cnpj"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

validate_cnpj() {
	local cnpj="$1"
	cnpj="${cnpj//[^0-9]/}"
	if [[ ${#cnpj} -ne 14 ]]; then
		echo "INVALID LENGTH (${#cnpj}): $1" >&2
		return 1
	fi

	# First check digit (weights: 5,4,3,2,9,8,7,6,5,4,3,2)
	local weights1=(5 4 3 2 9 8 7 6 5 4 3 2)
	local sum=0
	for ((i = 0; i < 12; i++)); do
		sum=$((sum + ${cnpj:i:1} * weights1[i]))
	done
	local rem=$((sum % 11))
	local d1=$((rem < 2 ? 0 : 11 - rem))

	# Second check digit (weights: 6,5,4,3,2,9,8,7,6,5,4,3,2)
	local weights2=(6 5 4 3 2 9 8 7 6 5 4 3 2)
	sum=0
	for ((i = 0; i < 13; i++)); do
		sum=$((sum + ${cnpj:i:1} * weights2[i]))
	done
	rem=$((sum % 11))
	local d2=$((rem < 2 ? 0 : 11 - rem))

	if [[ $d1 -ne ${cnpj:12:1} || $d2 -ne ${cnpj:13:1} ]]; then
		echo "INVALID CHECK DIGITS (expected ${d1}${d2} got ${cnpj:12:2}): $1" >&2
		return 1
	fi
}

# Test: unformatted output produces 14-digit valid CNPJ
echo -n "Testing unformatted… "
output=$("$SCRIPT")
if [[ ! "$output" =~ ^[0-9]{14}$ ]]; then
	echo "FAIL: expected 14 digits, got: $output"
	exit 1
fi
validate_cnpj "$output"
echo "OK"

# Test: formatted output produces valid CNPJ with mask
echo -n "Testing formatted… "
output=$("$SCRIPT" -f)
if [[ ! "$output" =~ ^[0-9]{2}\.[0-9]{3}\.[0-9]{3}/[0-9]{4}-[0-9]{2}$ ]]; then
	echo "FAIL: expected XX.XXX.XXX/XXXX-XX format, got: $output"
	exit 1
fi
validate_cnpj "$output"
echo "OK"

# Test: generate 100 random CNPJs and validate all
echo -n "Testing 100 random CNPJs… "
for _ in $(seq 1 100); do
	output=$("$SCRIPT")
	validate_cnpj "$output"
done
echo "OK"
