#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/general/bin/chave-nfe"

validate_chave() {
	local key="$1"
	key="${key//[^0-9]/}"
	if [[ ${#key} -ne 44 ]]; then
		echo "INVALID LENGTH (${#key}): $1" >&2
		return 1
	fi

	# Check digit: mod 11, weights 2→9 cycled right to left over first 43 digits
	local sum=0 weight=2
	for ((i = 42; i >= 0; i--)); do
		sum=$((sum + ${key:i:1} * weight))
		weight=$((weight + 1))
		((weight > 9)) && weight=2
	done
	local rem=$((sum % 11))
	local dv=$((rem < 2 ? 0 : 11 - rem))

	if [[ $dv -ne ${key:43:1} ]]; then
		echo "INVALID DV (expected $dv got ${key:43:1}): $1" >&2
		return 1
	fi

	# Validate structural fields
	[[ ${key:20:2} == "55" ]] || {
		echo "INVALID model: ${key:20:2}" >&2
		return 1
	}
	[[ ${key:34:1} == "1" ]] || {
		echo "INVALID tpEmis: ${key:34:1}" >&2
		return 1
	}
}

# Test: unformatted output produces 44-digit valid chave
echo -n "Testing unformatted… "
output=$("$SCRIPT")
if [[ ! "$output" =~ ^[0-9]{44}$ ]]; then
	echo "FAIL: expected 44 digits, got: $output"
	exit 1
fi
validate_chave "$output"
echo "OK"

# Test: formatted output
echo -n "Testing formatted… "
output=$("$SCRIPT" -f)
# 11 groups of 4 digits separated by spaces
if [[ ! "$output" =~ ^([0-9]{4}\ ){10}[0-9]{4}$ ]]; then
	echo "FAIL: expected 11 groups of 4 digits, got: $output"
	exit 1
fi
validate_chave "$output"
echo "OK"

# Test: custom UF
echo -n "Testing custom UF… "
output=$("$SCRIPT" -u 35)
if [[ ${output:0:2} != "35" ]]; then
	echo "FAIL: expected cUF=35, got ${output:0:2}"
	exit 1
fi
validate_chave "$output"
echo "OK"

# Test: custom CNPJ
echo -n "Testing custom CNPJ… "
output=$("$SCRIPT" -c 12345678000199)
if [[ ${output:6:14} != "12345678000199" ]]; then
	echo "FAIL: expected CNPJ=12345678000199, got ${output:6:14}"
	exit 1
fi
validate_chave "$output"
echo "OK"

# Test: generate 100 random chaves and validate all
echo -n "Testing 100 random chaves… "
for _ in $(seq 1 100); do
	output=$("$SCRIPT")
	validate_chave "$output"
done
echo "OK"
