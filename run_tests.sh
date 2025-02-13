#!/usr/bin/env bash

set -e
set -x

mkdir -p temp

package/bin/authV2 testdata/authV2_input.json temp/authV2_witness.wtns
snarkjs wchk testdata/authV2.r1cs temp/authV2_witness.wtns
