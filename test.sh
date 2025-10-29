#!/usr/bin/env bash

set -euo pipefail

show_help() {
    cat << EOF
Usage: $0 [OPTIONS] <circuit.circom>

Build and test circom circuits with witness calculation and optional
proof generation.

REQUIRED ARGUMENTS:
  <circuit.circom>          Path to the circom circuit file

OPTIONS:
  -l <path>                 Include path for circom compilation
                            Can be specified multiple times
                            Example: -l ~/circuits/lib -l ./common

  -o <directory>            Output directory for build artifacts
                            If not specified, a temporary directory is
                            created and REMOVED after script completes
                            If specified, directory persists after script
                            Example: -o ./build

  -i <inputs.json>          Input JSON file for witness calculation
                            Required if you want to generate a witness
                            Required if using -p for proof generation

  -p <ptau_file>            Powers of Tau file for proof generation
                            Enables r1cs generation and zkey creation
                            REQUIRES -i to be specified
                            Generates and verifies a zk-SNARK proof
                            Example: -p powersOfTau28_hez_final_18.ptau

  -h                        Show this help message and exit

WORKFLOW:
  Without -i and -p:
    - Compiles circuit to C++ with circom
    - Builds witness calculator library and executable

  With -i (no -p):
    - All of the above, plus:
    - Generates witness from input JSON

  With -i and -p:
    - All of the above, plus:
    - Generates r1cs constraint file
    - Creates or reuses cached zkey file (cached by r1cs MD5)
    - Generates zero-knowledge proof
    - Exports verification key (cached)
    - Verifies the generated proof

OUTPUT DIRECTORY BEHAVIOR:
  - WITHOUT -o: Creates temporary directory, removes after completion
    Use this for quick tests where you don't need to keep artifacts

  - WITH -o: Creates/uses specified directory, persists after completion
    Use this to keep build artifacts, witness, proof, and keys
    Zkey and verification key are cached here for reuse

REQUIREMENTS:
  - circom compiler
  - cmake, make, nasm (for building)
  - snarkjs (if using -p)
  - prover (rapidsnark, if using -p)

EXAMPLES:
  # Just build the witness calculator
  $0 -l ~/circomlib/circuits circuit.circom

  # Build and generate witness, keep output
  $0 -l ~/circomlib/circuits -o ./build \\
     -i inputs.json circuit.circom

  # Full workflow: build, witness, proof, and verify
  $0 -l ~/circomlib/circuits -o ./build \\
     -i inputs.json -p powersOfTau28_final_18.ptau \\
     circuit.circom

EOF
    exit 0
}

# Parse command line arguments
INCLUDE_PATHS=""
CIRCUIT_FILE=""
OUTPUT_DIR=""
INPUT_JSON=""
PTAU_FILE=""

# Process flags
while [[ $# -gt 0 ]]; do
    case $1 in
        -h)
            show_help
            ;;
        -l)
            if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
                echo "Error: -l requires a path argument"
                exit 1
            fi
            INCLUDE_PATHS="$INCLUDE_PATHS -l $2"
            shift 2
            ;;
        -o)
            if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
                echo "Error: -o requires a directory argument"
                exit 1
            fi
            if [[ -n "$OUTPUT_DIR" ]]; then
                echo "Error: -o can only be specified once"
                exit 1
            fi
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -i)
            if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
                echo "Error: -i requires a JSON file path"
                exit 1
            fi
            if [[ -n "$INPUT_JSON" ]]; then
                echo "Error: -i can only be specified once"
                exit 1
            fi
            INPUT_JSON="$2"
            shift 2
            ;;
        -p)
            if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
                echo "Error: -p requires a ptau file path"
                exit 1
            fi
            if [[ -n "$PTAU_FILE" ]]; then
                echo "Error: -p can only be specified once"
                exit 1
            fi
            PTAU_FILE="$2"
            shift 2
            ;;
        -*)
            echo "Error: Unknown option $1"
            echo "Try '$0 -h' for more information."
            exit 1
            ;;
        *)
            # This should be the circuit file (last positional argument)
            if [[ -n "$CIRCUIT_FILE" ]]; then
                echo "Error: Multiple circuit files specified"
                exit 1
            fi
            CIRCUIT_FILE="$1"
            shift
            ;;
    esac
done

# Validate required circuit file parameter
if [[ -z "$CIRCUIT_FILE" ]]; then
    echo "Error: Circuit .circom file is required"
    echo "Try '$0 -h' for more information."
    exit 1
fi

# Validate circuit file exists and has .circom extension
if [[ ! -f "$CIRCUIT_FILE" ]]; then
    echo "Error: Circuit file does not exist: $CIRCUIT_FILE"
    exit 1
fi

if [[ ! "$CIRCUIT_FILE" =~ \.circom$ ]]; then
    echo "Error: Circuit file must have .circom extension"
    exit 1
fi

# Validate input JSON file if provided
if [[ -n "$INPUT_JSON" && ! -f "$INPUT_JSON" ]]; then
    echo "Error: Input JSON file does not exist: $INPUT_JSON"
    exit 1
fi

# Validate ptau file and check for required executables
if [[ -n "$PTAU_FILE" ]]; then
    if [[ -z "$INPUT_JSON" ]]; then
        echo "Error: -p requires -i <inputs.json>"
        echo "Proof generation requires input JSON to generate witness"
        exit 1
    fi

    if [[ ! -f "$PTAU_FILE" ]]; then
        echo "Error: Ptau file does not exist: $PTAU_FILE"
        exit 1
    fi

    if ! command -v snarkjs &> /dev/null; then
        echo "Error: snarkjs executable not found in PATH"
        echo "Proof generation requires snarkjs"
        exit 1
    fi

    if ! command -v prover &> /dev/null; then
        echo "Error: prover executable not found in PATH"
        echo "Proof generation requires the prover tool"
        exit 1
    fi
fi

# Trim leading whitespace from INCLUDE_PATHS
INCLUDE_PATHS="${INCLUDE_PATHS# }"

echo "Circuit file: $CIRCUIT_FILE"
if [[ -n "$INCLUDE_PATHS" ]]; then
    echo "Include paths: $INCLUDE_PATHS"
fi

# Determine output directory: use provided or create temp
SHOULD_CLEANUP=false
if [[ -n "$OUTPUT_DIR" ]]; then
    # Create the directory if it doesn't exist and get absolute path
    mkdir -p "$OUTPUT_DIR"
    OUTDIR="$(cd "$OUTPUT_DIR" && pwd)"
    echo "Output directory: $OUTDIR"
else
    OUTDIR=$(mktemp -d)
    SHOULD_CLEANUP=true
    echo "Temporary directory: $OUTDIR"
fi

INSTALL_PREFIX="$OUTDIR/package"

# Ensure cleanup on exit if we created a temp dir
cleanup() {
    if [[ "$SHOULD_CLEANUP" == true && -d "$OUTDIR" ]]; then
        echo "Cleaning up temporary directory: $OUTDIR"
        rm -rf "$OUTDIR"
    fi
}
# todo: remove this
# don't cleanup for debugging
trap cleanup EXIT

# Build circom arguments
CIRCOM_ARGS="-c"
if [[ -n "$PTAU_FILE" ]]; then
    CIRCOM_ARGS="$CIRCOM_ARGS --r1cs"
fi
CIRCOM_ARGS="$CIRCOM_ARGS $INCLUDE_PATHS"

# Run circom command
echo "Running circom..."
circom $CIRCOM_ARGS -o "$OUTDIR" "$CIRCUIT_FILE"

echo "Circom compilation completed successfully"
echo "Output files are in: $OUTDIR"

# Calculate path to generated .cpp file
CIRCUIT_NAME=$(basename "$CIRCUIT_FILE" .circom)
CIRCUIT_CPP_PATH="$OUTDIR/${CIRCUIT_NAME}_cpp/${CIRCUIT_NAME}.cpp"
echo "Generated C++ file: $CIRCUIT_CPP_PATH"

# Get the directory where this script is located (repo root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect number of CPUs for parallel build
NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 8)

echo "Running cmake..."
cmake "$SCRIPT_DIR" \
    -B "$OUTDIR/build" \
    -DTARGET_PLATFORM=macos_arm64 \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -DCIRCUIT_FILE="$CIRCUIT_CPP_PATH"

echo "Building with make -j $NPROC..."
make -C "$OUTDIR/build" -j "$NPROC"

echo "Installing..."
make -C "$OUTDIR/build" install

# Run witness calculator if input JSON was provided
if [[ -n "$INPUT_JSON" ]]; then
    WITNESS_CALC="$INSTALL_PREFIX/bin/$CIRCUIT_NAME"
    WITNESS_OUTPUT="$OUTDIR/${CIRCUIT_NAME}.wtns"

    echo "Running witness calculator..."
    echo "  Executable: $WITNESS_CALC"
    echo "  Input JSON: $INPUT_JSON"
    echo "  Output witness: $WITNESS_OUTPUT"

    "$WITNESS_CALC" "$INPUT_JSON" "$WITNESS_OUTPUT"

    echo "Witness generated successfully: $WITNESS_OUTPUT"

    # Generate proof if ptau file was provided
    if [[ -n "$PTAU_FILE" ]]; then
        # Generate zkey if needed
        R1CS_PATH="$OUTDIR/${CIRCUIT_NAME}.r1cs"
        echo "R1CS file: $R1CS_PATH"

        # Calculate MD5 of r1cs file
        if command -v md5sum &> /dev/null; then
            R1CS_MD5=$(md5sum "$R1CS_PATH" | awk '{print $1}')
        else
            R1CS_MD5=$(md5 -q "$R1CS_PATH")
        fi
        echo "R1CS MD5: $R1CS_MD5"

        ZKEY_PATH="$OUTDIR/${CIRCUIT_NAME}_${R1CS_MD5}.zkey"
        ZKEY_TEMP="$OUTDIR/${CIRCUIT_NAME}_${R1CS_MD5}_0000.zkey"

        if [[ -f "$ZKEY_PATH" ]]; then
            echo "Zkey file already exists: $ZKEY_PATH"
        else
            echo "Generating zkey file..."

            # Generate entropy
            ENTROPY1=$(head -c 64 /dev/urandom | \
                       od -An -tx1 -v | tr -d ' \n')

            # Setup phase
            echo "Running groth16 setup..."
            snarkjs groth16 setup "$R1CS_PATH" "$PTAU_FILE" \
                    "$ZKEY_TEMP"

            # Contribution phase
            echo "Running zkey contribute..."
            snarkjs zkey contribute "$ZKEY_TEMP" "$ZKEY_PATH" \
                    --name="1st Contribution" -v -e="$ENTROPY1"

            # Clean up temporary file
            rm -f "$ZKEY_TEMP"

            echo "Zkey generated: $ZKEY_PATH"
        fi

        # Generate proof
        PROOF_JSON="$OUTDIR/${CIRCUIT_NAME}_proof.json"
        PUBLIC_JSON="$OUTDIR/${CIRCUIT_NAME}_public.json"

        echo "Running prover..."
        echo "  Zkey: $ZKEY_PATH"
        echo "  Witness: $WITNESS_OUTPUT"
        echo "  Proof output: $PROOF_JSON"
        echo "  Public output: $PUBLIC_JSON"

        prover "$ZKEY_PATH" "$WITNESS_OUTPUT" \
               "$PROOF_JSON" "$PUBLIC_JSON"

        echo "Proof generated successfully: $PROOF_JSON"
        echo "Public signals: $PUBLIC_JSON"

        # Export verification key and verify proof
        VK_PATH="$OUTDIR/${CIRCUIT_NAME}_${R1CS_MD5}_vk.json"

        if [[ ! -f "$VK_PATH" ]]; then
            echo "Exporting verification key..."
            snarkjs zkey export verificationkey "$ZKEY_PATH" \
                    "$VK_PATH"
            echo "Verification key exported: $VK_PATH"
        else
            echo "Using existing verification key: $VK_PATH"
        fi

        echo "Verifying proof..."
        if snarkjs g16v "$VK_PATH" "$PUBLIC_JSON" "$PROOF_JSON"; then
            echo "Proof verification: SUCCESS"
        else
            echo "Proof verification: FAILED"
            exit 1
        fi
    fi
fi