#!/bin/bash
#
# Run a single benchmark with ETISS
#
# Usage: ./run-benchmark.sh --program PROGRAM [OPTIONS]
#
#   --program PROGRAM         Program to run (required)
#   --profile PROFILE         Examples build profile (default: default)
#   --etiss-variant VARIANT   ETISS build variant (default: default)
#   --jit JIT                JIT compiler: TCC, GCC, LLVM (default: TCC)
#   --block-size SIZE         Max block size for JIT (default: 100)
#
# Examples:
#   ./run-benchmark.sh --program dhry                          # Run dhry with defaults
#   ./run-benchmark.sh --program hello_world --profile scalar  # Run with scalar profile
#   ./run-benchmark.sh --program dhry --jit TCC --block-size 50  # Full configuration
#

set -e

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPTS_ROOT}/scripts/common.sh"

# Default values
PROGRAM=""
PROFILE="default"
ETISS_VARIANT="default"
JIT="TCC"
BLOCK_SIZE="100"
GCC_OPT_LEVEL="3"
LLVM_OPT_LEVEL="3"
FAST_JIT=""
OPTIMIZATION_THREADS=""
JIT_STATS_JSON=""

# Parse named arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: $0 --program PROGRAM [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --program PROGRAM         Program to run (required)"
            echo "  --profile PROFILE         Examples build profile (default: default)"
            echo "  --etiss-variant VARIANT   ETISS build variant (default: default)"
            echo "  --jit JIT                JIT compiler: TCC, GCC, LLVM (default: TCC)"
            echo "  --block-size SIZE         Max block size (default: 100)"
            echo "  --gcc-opt-level LEVEL     GCC JIT optimization level (default: 3)"
            echo "  --llvm-opt-level LEVEL    LLVM JIT optimization level (default: 3)"
            echo "  --fast-jit JIT            Fast JIT compiler for jit.fast_type (optional)"
            echo "  --optimization-threads N  Number of background optimization threads (optional)"
            echo "  --jit-stats-json PATH     Path to export JIT statistics as JSON (optional)"
            exit 0
            ;;
        --program)
            PROGRAM="$2"
            shift 2
            ;;
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --etiss-variant)
            ETISS_VARIANT="$2"
            shift 2
            ;;
        --jit)
            JIT="$2"
            shift 2
            ;;
        --block-size)
            BLOCK_SIZE="$2"
            shift 2
            ;;
        --gcc-opt-level)
            GCC_OPT_LEVEL="$2"
            shift 2
            ;;
        --llvm-opt-level)
            LLVM_OPT_LEVEL="$2"
            shift 2
            ;;
        --fast-jit)
            FAST_JIT="$2"
            shift 2
            ;;
        --optimization-threads)
            OPTIMIZATION_THREADS="$2"
            shift 2
            ;;
        --jit-stats-json)
            JIT_STATS_JSON="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Validate required arguments
if [[ -z "$PROGRAM" ]]; then
    error "Missing required argument: --program PROGRAM"
fi

# Load configuration
load_config

# Get ETISS build directory
ETISS_BUILD_DIR=$(get_profile_field "$ETISS_VARIANT" "build_dir" "etiss")
if [[ -z "$ETISS_BUILD_DIR" ]]; then
    error "Unknown ETISS variant: $ETISS_VARIANT"
fi
ETISS_BIN="${ETISS_ROOT}/${ETISS_BUILD_DIR}/bin/bare_etiss_processor"

# Check if ETISS binary exists
if [[ ! -f "$ETISS_BIN" ]]; then
    error "ETISS binary not found: $ETISS_BIN\nDid you build ETISS variant '$ETISS_VARIANT'?"
fi

# Get example build directory
BUILD_DIR=$(get_profile_field "$PROFILE" "build_dir")
if [[ -z "$BUILD_DIR" ]]; then
    error "Unknown examples profile: $PROFILE"
fi

INI_FILE="${EXAMPLES_ROOT}/${BUILD_DIR}/install/ini/${PROGRAM}.ini"

# Check if INI file exists
if [[ ! -f "$INI_FILE" ]]; then
    error "Program INI file not found: $INI_FILE\nDid you build '$PROGRAM' with profile '$PROFILE'?"
fi

# Create temporary configuration
TEMP_INI=$(mktemp)
trap "rm -f $TEMP_INI" EXIT

# Build fast_jit line if set
FAST_JIT_LINE=""
if [[ -n "$FAST_JIT" ]]; then
    FAST_JIT_LINE="jit.fast_type=${FAST_JIT}JIT"
fi

# Build optimization_threads line if set
OPT_THREADS_LINE=""
if [[ -n "$OPTIMIZATION_THREADS" ]]; then
    OPT_THREADS_LINE="jit.optimization_threads=$OPTIMIZATION_THREADS"
fi

# Build jit_stats_json line if set
JIT_STATS_JSON_LINE=""
if [[ -n "$JIT_STATS_JSON" ]]; then
    JIT_STATS_JSON_LINE="jit.stats.json_output=$JIT_STATS_JSON"
fi

cat > "$TEMP_INI" << EOF
[StringConfigurations]
jit.type=${JIT}JIT
${FAST_JIT_LINE}
${JIT_STATS_JSON_LINE}
jit.gcc.cleanup=true
jit.gcc.opt_level=${GCC_OPT_LEVEL}
jit.gcc.quiet=true
jit.llvm.opt_level=${LLVM_OPT_LEVEL}
jit.llvm.quiet=true

[IntConfigurations]
etiss.max_block_size=$BLOCK_SIZE
etiss.loglevel=1
${OPT_THREADS_LINE}

EOF

log "========================================="
log "Running benchmark: $PROGRAM"
log "========================================="
log "  Profile: $PROFILE"
log "  ETISS variant: $ETISS_VARIANT"
log "  JIT: $JIT"
if [[ -n "$FAST_JIT" ]]; then
    log "  Fast JIT: $FAST_JIT"
fi
if [[ -n "$OPTIMIZATION_THREADS" ]]; then
    log "  Optimization threads: $OPTIMIZATION_THREADS"
fi
log "  Block size: $BLOCK_SIZE"
log "  GCC opt level: $GCC_OPT_LEVEL"
log "  LLVM opt level: $LLVM_OPT_LEVEL"
log "  ETISS binary: $ETISS_BIN"
log "  INI file: $INI_FILE"
log ""

# Run ETISS
"$ETISS_BIN" \
    -i"$INI_FILE" \
    -i"$TEMP_INI" \
    --arch.cpu="$DEFAULT_ETISS_ARCH"
