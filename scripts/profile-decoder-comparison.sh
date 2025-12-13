#!/bin/bash
#
# Comprehensive Decoder Comparison Script
#
# This script runs extensive profiling to compare old vs new decoder
# across different simulation run counts and programs.
#
# Usage: ./profile-decoder-comparison.sh [--programs PROGRAMS] [--run-counts COUNTS]
#
#   --programs PROGRAMS    Comma-separated list of programs (default: all)
#   --run-counts COUNTS    Comma-separated list of run counts (default: 1,2,4,8,16)
#   --example-profile PROF Example build profile (default: default)
#   --skip-build          Skip building ETISS and examples
#
# Examples:
#   ./profile-decoder-comparison.sh
#   ./profile-decoder-comparison.sh --programs dhry,coremark
#   ./profile-decoder-comparison.sh --run-counts 1,4,16
#   ./profile-decoder-comparison.sh --skip-build
#

set -e

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPTS_ROOT}/scripts/common.sh"

# Default values
PROGRAMS=""  # Empty means all programs
RUN_COUNTS="1,2,4,8,16"
EXAMPLE_PROFILE="default"
SKIP_BUILD=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --programs PROGRAMS      Comma-separated list of programs (default: all)"
            echo "  --run-counts COUNTS      Comma-separated list of run counts (default: 1,2,4,8,16)"
            echo "  --example-profile PROF   Example build profile (default: default)"
            echo "  --skip-build            Skip building ETISS and examples"
            echo ""
            exit 0
            ;;
        --programs)
            PROGRAMS="$2"
            shift 2
            ;;
        --run-counts)
            RUN_COUNTS="$2"
            shift 2
            ;;
        --example-profile)
            EXAMPLE_PROFILE="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD="yes"
            shift
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Load configuration
load_config

# Create results directory with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="${SCRIPTS_ROOT}/results/decoder_comparison_${TIMESTAMP}"
mkdir -p "$RESULTS_DIR"

log "======================================================================="
log "Decoder Comparison Profiling"
log "======================================================================="
log "Results directory: $RESULTS_DIR"
log "Run counts: $RUN_COUNTS"
log "Example profile: $EXAMPLE_PROFILE"
log "Programs: ${PROGRAMS:-all}"
log ""

# Build ETISS variants if not skipped
if [[ -z "$SKIP_BUILD" ]]; then
    log "Building ETISS decoder variants..."
    
    log "  Building OLD decoder variant..."
    "${SCRIPTS_ROOT}/scripts/build-etiss.sh" --variant etiss_profile_old_decoder --clean
    
    log "  Building NEW decoder variant..."
    "${SCRIPTS_ROOT}/scripts/build-etiss.sh" --variant etiss_profile_new_decoder --clean
    
    log "ETISS builds complete!"
    log ""
else
    log "Skipping ETISS builds (using existing binaries)"
    log ""
fi

# Convert run counts to array
IFS=',' read -ra RUN_COUNT_ARRAY <<< "$RUN_COUNTS"

# Build examples for each run count if not skipped
if [[ -z "$SKIP_BUILD" ]]; then
    log "Building examples with different run counts..."
    
    for runs in "${RUN_COUNT_ARRAY[@]}"; do
        PROFILE="${EXAMPLE_PROFILE}_runs${runs}"
        log "  Building examples with ${runs} run(s): profile=$PROFILE"
        "${SCRIPTS_ROOT}/scripts/build-examples.sh" --profile "$PROFILE" --clean
    done
    
    log "Example builds complete!"
    log ""
else
    log "Skipping example builds (using existing binaries)"
    log ""
fi

# Determine programs to profile
if [[ -n "$PROGRAMS" ]]; then
    IFS=',' read -ra PROGRAM_ARRAY <<< "$PROGRAMS"
else
    # Get all available programs from the examples directory
    EXAMPLE_BUILD_DIR="${EXAMPLES_ROOT}/build_runs1/install/bin"
    if [[ ! -d "$EXAMPLE_BUILD_DIR" ]]; then
        error "Example directory not found: $EXAMPLE_BUILD_DIR"
    fi
    PROGRAM_ARRAY=($(ls "$EXAMPLE_BUILD_DIR" | grep -v '\.elf$' || true))
fi

log "Programs to profile: ${PROGRAM_ARRAY[*]}"
log ""

# Create summary file
SUMMARY_FILE="${RESULTS_DIR}/summary.txt"
cat > "$SUMMARY_FILE" <<EOF
Decoder Comparison Profiling Results
=====================================
Date: $(date)
Run Counts: $RUN_COUNTS
Programs: ${PROGRAM_ARRAY[*]}

EOF

# Run profiling for each combination
TOTAL_RUNS=$((${#RUN_COUNT_ARRAY[@]} * ${#PROGRAM_ARRAY[@]} * 2))
CURRENT_RUN=0

for runs in "${RUN_COUNT_ARRAY[@]}"; do
    for program in "${PROGRAM_ARRAY[@]}"; do
        EXAMPLE_BUILD_PROFILE="${EXAMPLE_PROFILE}_runs${runs}"
        
        # Profile with OLD decoder
        CURRENT_RUN=$((CURRENT_RUN + 1))
        log "[$CURRENT_RUN/$TOTAL_RUNS] Profiling: program=$program, runs=$runs, decoder=OLD"
        
        OUTPUT_DIR="${RESULTS_DIR}/old_decoder/${program}_runs${runs}"
        mkdir -p "$OUTPUT_DIR"
        
        set +e
        python3 "${SCRIPTS_ROOT}/tools/profiler.py" \
            --etiss-variant etiss_profile_old_decoder \
            --example-profile "$EXAMPLE_BUILD_PROFILE" \
            --program "$program" \
            --output-dir "$OUTPUT_DIR" \
            --duration 60 \
            --frequency 999 2>&1 | tee "${OUTPUT_DIR}/profiler.log"
        OLD_STATUS=$?
        set -e
        
        if [[ $OLD_STATUS -ne 0 ]]; then
            log "  WARNING: OLD decoder profiling failed for $program (runs=$runs)"
            echo "FAILED: $program (runs=$runs) OLD decoder" >> "$SUMMARY_FILE"
        else
            log "  ✓ OLD decoder profiling complete"
        fi
        
        # Profile with NEW decoder
        CURRENT_RUN=$((CURRENT_RUN + 1))
        log "[$CURRENT_RUN/$TOTAL_RUNS] Profiling: program=$program, runs=$runs, decoder=NEW"
        
        OUTPUT_DIR="${RESULTS_DIR}/new_decoder/${program}_runs${runs}"
        mkdir -p "$OUTPUT_DIR"
        
        set +e
        python3 "${SCRIPTS_ROOT}/tools/profiler.py" \
            --etiss-variant etiss_profile_new_decoder \
            --example-profile "$EXAMPLE_BUILD_PROFILE" \
            --program "$program" \
            --output-dir "$OUTPUT_DIR" \
            --duration 60 \
            --frequency 999 2>&1 | tee "${OUTPUT_DIR}/profiler.log"
        NEW_STATUS=$?
        set -e
        
        if [[ $NEW_STATUS -ne 0 ]]; then
            log "  WARNING: NEW decoder profiling failed for $program (runs=$runs)"
            echo "FAILED: $program (runs=$runs) NEW decoder" >> "$SUMMARY_FILE"
        else
            log "  ✓ NEW decoder profiling complete"
        fi
        
        log ""
    done
done

log "======================================================================="
log "Profiling Complete!"
log "======================================================================="
log "Results saved to: $RESULTS_DIR"
log ""
log "Summary:"
cat "$SUMMARY_FILE"
log ""
log "To analyze results, use:"
log "  python3 ${SCRIPTS_ROOT}/tools/analyze_results.py --results-dir $RESULTS_DIR"
log ""
