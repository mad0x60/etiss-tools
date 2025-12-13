#!/bin/bash
#
# Build RISC-V examples with configurable profiles
#
# Usage: ./build-examples.sh --profile PROFILE [--program PROGRAM] [--clean]
#
#   --profile PROFILE  Build profile (default: default)
#   --program PROGRAM  Specific program to build (default: all programs)
#   --clean           Clean build directory before building
#
# Examples:
#   ./build-examples.sh --profile default               # Build all with default profile
#   ./build-examples.sh --profile scalar                # Build all with scalar profile  
#   ./build-examples.sh --profile default --program hello_world  # Build hello_world with default
#   ./build-examples.sh --profile manual --program dhry --clean  # Clean + build dhry with manual
#

set -e

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPTS_ROOT}/scripts/common.sh"

# Default values
PROFILE="default"
PROGRAM=""
CLEAN=""

# Parse named arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: $0 --profile PROFILE [--program PROGRAM] [--clean]"
            echo ""
            echo "Options:"
            echo "  --profile PROFILE  Build profile (default: default)"
            echo "  --program PROGRAM  Specific program to build (default: all)"
            echo "  --clean           Clean build directory before building"
            echo ""
            echo "Profiles:"
            list_profiles "examples"
            exit 0
            ;;
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --program)
            PROGRAM="$2"
            shift 2
            ;;
        --clean)
            CLEAN="clean"
            shift
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Load configuration
load_config

# Check toolchain
check_command cmake

# Get profile configuration fields
ARCH=$(get_profile_field "$PROFILE" "arch")
ABI=$(get_profile_field "$PROFILE" "abi")
EXTRA_FLAGS=$(get_profile_field "$PROFILE" "cmake_flags")
BUILD_DIR=$(get_profile_field "$PROFILE" "build_dir")
RUNS_COUNT=$(get_profile_field "$PROFILE" "runs_count")

# Default to 1 if not specified in config
RUNS_COUNT=${RUNS_COUNT:-1}

if [[ -z "$ARCH" ]] || [[ -z "$ABI" ]] || [[ -z "$BUILD_DIR" ]]; then
    error "Unknown profile: $PROFILE"
fi

log "========================================="
log "Building RISC-V examples: $PROFILE"
log "========================================="
log "Repository: $(get_git_info "$EXAMPLES_ROOT")"
log "  ARCH: $ARCH"
log "  ABI: $ABI"
log "  Extra flags: ${EXTRA_FLAGS:-none}"
log "  Build dir: $BUILD_DIR"
log "  Toolchain: $RISCV_TOOLCHAIN_PREFIX"
log "  Simulation runs: $RUNS_COUNT"
log ""

cd "$EXAMPLES_ROOT"

# Clean if requested
if [[ "$CLEAN" == "clean" ]]; then
    log "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
fi

# Determine toolchain file
CMAKE_TOOLCHAIN_FILE="${EXAMPLES_ROOT}/rv32gc-toolchain.cmake"

# Check if toolchain file exists
if [[ ! -f "$CMAKE_TOOLCHAIN_FILE" ]]; then
    error "Toolchain file not found: $CMAKE_TOOLCHAIN_FILE"
fi

# Configure
log "Configuring CMake..."
cmake -S . -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE="$CMAKE_BUILD_TYPE" \
    -DCMAKE_INSTALL_PREFIX="${EXAMPLES_ROOT}/${BUILD_DIR}/install" \
    -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN_FILE" \
    -DRISCV_TOOLCHAIN_BASENAME="$RISCV_TOOLCHAIN_BASENAME" \
    -DRISCV_TOOLCHAIN_PREFIX="$RISCV_TOOLCHAIN_PREFIX" \
    -DRISCV_ARCH="$ARCH" \
    -DRISCV_ABI="$ABI" \
    -DSIMULATION_RUNS_COUNT="$RUNS_COUNT" \
    $EXTRA_FLAGS

# Build
if [[ -n "$PROGRAM" ]]; then
    log "Building program: $PROGRAM"
    cmake --build "$BUILD_DIR" -j"$BUILD_JOBS" -t "$PROGRAM"
else
    log "Building all examples..."
    cmake --build "$BUILD_DIR" -j"$BUILD_JOBS"
fi

# Install
log "Installing to ${BUILD_DIR}/install..."
cmake --install "$BUILD_DIR"

log ""
log "========================================="
log "Build complete!"
log "========================================="
log "Installed to: ${EXAMPLES_ROOT}/${BUILD_DIR}/install"
log ""
