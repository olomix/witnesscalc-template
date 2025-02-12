#!/usr/bin/env bash

set -e
set -x

mkdir -p temp

package/bin/authV2 \
  testdata/authV2_input.json \
  temp/authV2_witness.wtns
snarkjs groth16 prove \
  circuits/authV2/circuit_final.zkey \
  temp/authV2_witness.wtns \
  temp/authV2_proof.json \
  temp/authV2_public.json
snarkjs groth16 verify \
  circuits/authV2/verification_key.json \
  temp/authV2_public.json \
  temp/authV2_proof.json
