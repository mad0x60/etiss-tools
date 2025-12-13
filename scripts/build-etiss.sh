#!/bin/bash
#
# Build ETISS with configurable variants
#
# Usage: ./build-etiss.sh --variant VARIANT [--clean]
#
#   --variant VARIANT: default, debug, tcc, llvm, all (default: default)
#   --clean:           Clean build directory before building
#
# Examples:
#   ./build-etiss.sh --variant default       # Build default variant
#   ./build-etiss.sh --variant debug --clean # Clean + build debug variant
#   ./build-etiss.sh --variant tcc           # Build TCC-only variant
#

set -e

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPTS_ROOT}/scripts/common.sh"

# Default values
VARIANT="default"
CLEAN=""

# Parse named arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: $0 --variant VARIANT [--clean]"
            echo ""
            echo "Options:"
            echo "  --variant VARIANT  Build variant (default: default)"
            echo "  --clean           Clean build directory before building"
            echo ""
            echo "Variants:"
            list_profiles "etiss"
            exit 0
            ;;
        --variant)
            VARIANT="$2"
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

# Get variant configuration fields
CMAKE_FLAGS=$(get_profile_field "$VARIANT" "cmake_flags" "etiss")
BUILD_DIR=$(get_profile_field "$VARIANT" "build_dir" "etiss")

if [[ -z "$CMAKE_FLAGS" ]] || [[ -z "$BUILD_DIR" ]]; then
    error "Unknown ETISS variant: $VARIANT"
fi

log "========================================="
log "Building ETISS variant: $VARIANT"
log "========================================="
log "Repository: $(get_git_info "$ETISS_ROOT")"
log "CMake flags: $CMAKE_FLAGS"
log "Build directory: $ETISS_ROOT/$BUILD_DIR"
log ""

cd "$ETISS_ROOT"

# Clean if requested
if [[ "$CLEAN" == "clean" ]]; then
    log "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
fi

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Configure
log "Configuring with CMake..."
eval cmake $CMAKE_FLAGS ..

# Build
log "Building with $BUILD_JOBS parallel jobs..."
cmake --build . -j"$BUILD_JOBS"

log ""
log "========================================="
log "ETISS build complete!"
log "========================================="
log "Binary: $ETISS_ROOT/$BUILD_DIR/bin/bare_etiss_processor"
log ""
