#!/bin/sh
# Runs all four formal verification and static analysis suites for nospeaker:
#   1. Lean 4.36 kernel proof checker (`NoSpeakerSpec.lean`)
#   2. Z3 SMT-LIB2 IEEE-754 & BitVector prover (`ieee754_and_bv_proofs.smt2`)
#   3. Z3Py multi-theory security, thermal & real-time prover (`z3_security_performance_suite.py`)
#   4. Swift 6 strict-concurrency & capability contract typechecker (`HardenedSecurityContracts.swift`)
set -eu
cd -- "$(dirname -- "$0")"

echo "[1/4] Checking Lean 4 formal proofs (NoSpeakerSpec.lean)…"
lean NoSpeakerSpec.lean

echo ""
echo "[2/4] Running Z3 SMT-LIB2 IEEE-754 & BitVector proofs (ieee754_and_bv_proofs.smt2)…"
z3 ieee754_and_bv_proofs.smt2

echo ""
echo "[3/4] Running Z3Py security, thermal & real-time proof suite (z3_security_performance_suite.py)…"
python3 z3_security_performance_suite.py

echo ""
echo "[4/4] Typechecking HardenedSecurityContracts.swift (Swift 6 -strict-concurrency=complete -warnings-as-errors)…"
swiftc -module-cache-path /tmp/swift-module-cache \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -O \
    -target arm64-apple-macos12 \
    -parse-as-library \
    -typecheck HardenedSecurityContracts.swift

swiftc -module-cache-path /tmp/swift-module-cache \
    -swift-version 6 \
    -strict-concurrency=complete \
    -warnings-as-errors \
    -O \
    -target x86_64-apple-macos13 \
    -parse-as-library \
    -typecheck HardenedSecurityContracts.swift

echo ""
echo "All formal proofs and Swift 6 strict-concurrency checks passed."
