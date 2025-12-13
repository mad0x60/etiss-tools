#!/bin/bash
#
# Common utilities for ETISS build scripts
#

# Get the scripts root directory
SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load configuration
load_config() {
    local config_file="${SCRIPTS_ROOT}/config/env.conf"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
    else
        echo "Error: Config file not found: $config_file" >&2
        exit 1
    fi
}

# Get profile from JSON config files
# Usage: get_profile PROFILE_NAME [examples|etiss]
get_profile() {
    local profile_name=$1
    local config_type=${2:-examples}
    local config_file
    
    # Determine which config file to use
    if [[ "$config_type" == "etiss" ]]; then
        # Strip etiss_ prefix if present for JSON lookup
        profile_name=${profile_name#etiss_}
        config_file="${SCRIPTS_ROOT}/config/etiss-builds.json"
    else
        config_file="${SCRIPTS_ROOT}/config/example-builds.json"
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        error "jq is required but not installed. Install it with: brew install jq"
    fi
    
    # Get profile from JSON
    jq -r ".builds.\"${profile_name}\"" "$config_file" 2>/dev/null
}

# Get a specific field from a profile
# Usage: get_profile_field PROFILE_NAME FIELD_NAME [examples|etiss]
get_profile_field() {
    local profile_name=$1
    local field_name=$2
    local config_type=${3:-examples}
    local config_file
    
    # Determine which config file to use
    if [[ "$config_type" == "etiss" ]]; then
        # Strip etiss_ prefix if present for JSON lookup
        profile_name=${profile_name#etiss_}
        config_file="${SCRIPTS_ROOT}/config/etiss-builds.json"
    else
        config_file="${SCRIPTS_ROOT}/config/example-builds.json"
    fi
    
    # Get field from JSON
    jq -r ".builds.\"${profile_name}\".${field_name} // empty" "$config_file" 2>/dev/null
}

# Log with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Log error and exit
error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
    exit 1
}

# Check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Required command '$1' not found"
    fi
}

# List available profiles
list_profiles() {
    local profile_type=$1
    local config_file
    
    echo "Available profiles:"
    if [[ "$profile_type" == "etiss" ]]; then
        config_file="${SCRIPTS_ROOT}/config/etiss-builds.json"
    else
        config_file="${SCRIPTS_ROOT}/config/example-builds.json"
    fi
    
    # List profile names with descriptions
    jq -r '.builds | to_entries[] | "  - \(.key): \(.value.description)"' "$config_file" 2>/dev/null
}

# Get git commit info
get_git_info() {
    local repo_path=$1
    if [[ -d "$repo_path/.git" ]]; then
        cd "$repo_path"
        local commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        local dirty=""
        if ! git diff-index --quiet HEAD -- 2>/dev/null; then
            dirty=" (dirty)"
        fi
        echo "${branch}@${commit}${dirty}"
    else
        echo "unknown"
    fi
}
