#!/bin/bash

# Script to check for circular dependencies in files changed in the current PR
# Requires: git, madge (npm install -g madge)

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global counters
TOTAL_FILES=0
FILES_WITH_CIRCULAR_DEPS=0
CIRCULAR_DEPS_FOUND=0

# Verbose flag
VERBOSE=false

# Function to parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [--verbose|-v] [--help|-h]"
                echo ""
                echo "Options:"
                echo "  --verbose, -v    Show detailed output including info and success messages"
                echo "  --help, -h       Show this help message"
                echo ""
                echo "By default, only errors and warnings are shown."
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done
}

# Function to print colored output
print_info() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

print_info_must() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

print_success() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${GREEN}[SUCCESS]${NC} $1"
    fi
}

print_success_must() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_error "Not in a git repository. Please run this script from within a git repository."
        exit 1
    fi
    
    local repo_root
    repo_root=$(git rev-parse --show-toplevel)
    print_info_must "Git repository root: $repo_root"

}

# Function to check if madge is installed
check_dependencies() {
    if ! command -v madge &> /dev/null; then
        print_error "madge is not installed. Please install it with: npm install -g madge"
        exit 1
    fi
}

# Function to get the base branch
get_base_branch() {
    local base_branch=""

    # Try to get base branch from GitHub PR first
    if command -v gh &> /dev/null; then
        base_branch=$(gh pr view --json baseRefName --jq '.baseRefName' 2>/dev/null || true)
        
        if [ -n "$base_branch" ]; then
            base_branch="origin/$base_branch"
            echo "$base_branch"
            return 0
        else
            print_warning "Could not get base branch from GitHub PR (not in a PR or gh command failed)" >&2
        fi
    else
        print_warning "GitHub CLI (gh) not installed, falling back to default branch detection" >&2
    fi
}

# Function to get changed files in the current PR
get_changed_files() {
    local base_branch="$1"
    local current_branch
    current_branch=$(git branch --show-current)

    
    print_info_must "Current branch: $current_branch"
    print_info_must "Base branch: $base_branch"
    
    print_info "Git diff command: git diff --name-only $base_branch...HEAD"

    echo "" >&2

    print_info_must "Files changed in current PR:"
    
    local changed_files
    changed_files=$(git diff --name-only "$base_branch"...HEAD)
    
    if [ -z "$changed_files" ]; then
        print_warning "No files changed between $current_branch and $base_branch"
        print_info "This usually means:"
        print_info "  - You're on the base branch ($base_branch) with no new commits"
        print_info "  - Your branch is up to date with the base branch"
        print_info "  - There are no committed changes in your branch"
        return 1
    fi
    
    print_info "Found $(echo "$changed_files" | wc -l | tr -d ' ') changed files in PR ($current_branch vs $base_branch)" >&2
    
    echo "$changed_files"
}

# Function to filter for JavaScript/TypeScript files
filter_js_ts_files() {
    local changed_files="$1"
    local js_ts_files
    js_ts_files=$(echo "$changed_files" | grep -E '\.(js|jsx|ts|tsx|mjs|cjs)$' || true)
    
    if [ -z "$js_ts_files" ]; then
        print_warning "No JavaScript/TypeScript files found in changed files"
        return 1
    fi
    
    print_info "JavaScript/TypeScript files to analyze:"
    echo "$js_ts_files" | while read -r file; do
        echo "  - $file"
    done >&2  # Send to stderr so it doesn't interfere with return value
    echo "" >&2
    
    echo "$js_ts_files"
}

# Function to filter circular dependencies for a specific file
filter_circular_deps_for_file() {
    local file="$1"
    local circular_output="$2"
    
    # Get the base name of the analyzed file for comparison
    local analyzed_file_base
    local analyzed_file_path_no_ext
    analyzed_file_base=$(basename "$file" | sed 's/\.[^.]*$//')
    analyzed_file_path_no_ext=$(echo "$file" | sed 's/\.[^.]*$//')
    
    # Filter circular dependencies to only show those involving the analyzed file
    local filtered_circular=""
    while IFS= read -r line; do
        if [ -n "$line" ] && (echo "$line" | grep -q "$analyzed_file_base" || echo "$line" | grep -q "$analyzed_file_path_no_ext"); then
            if [ -z "$filtered_circular" ]; then
                filtered_circular="$line"
            else
                filtered_circular="$filtered_circular"$'\n'"$line"
            fi
        fi
    done <<< "$circular_output"
    
    echo "$filtered_circular"
}

# Function to analyze a single file for circular dependencies
analyze_file() {
    local file="$1"
    local full_path
    
    # Convert relative path to absolute path if needed
    if [[ "$file" = /* ]]; then
        full_path="$file"
    else
        full_path="$(pwd)/$file"
    fi
    
    if [ ! -f "$full_path" ]; then
        print_warning "File not found: $file (may have been deleted)" >&2
        return
    fi
    
    TOTAL_FILES=$((TOTAL_FILES + 1))
    print_info "Analyzing: $file"
    
    # Run madge to check for circular dependencies using the full path
    local circular_output
    circular_output=$(madge --circular "$full_path" 2>/dev/null || true)
    
    if [ -n "$circular_output" ]; then
        local filtered_circular
        filtered_circular=$(filter_circular_deps_for_file "$file" "$circular_output")
        
        if [ -n "$filtered_circular" ]; then
            FILES_WITH_CIRCULAR_DEPS=$((FILES_WITH_CIRCULAR_DEPS + 1))
            
            # Count the number of circular dependency chains
            local chains
            chains=$(echo "$filtered_circular" | grep -c ">" || true)
            CIRCULAR_DEPS_FOUND=$((CIRCULAR_DEPS_FOUND + chains))
            
            print_error "Circular dependencies involving $file:"
            
            MAX_CIRCULAR_FILES_PER_OUTPUT=5

            if [ $chains -le $MAX_CIRCULAR_FILES_PER_OUTPUT ]; then
                # Show all if MAX_CIRCULAR_FILES_PER_OUTPUT or fewer
                echo "$filtered_circular" | sed 's/^/    /'
            else
                # Show first MAX_CIRCULAR_FILES_PER_OUTPUT and save all to file
                print_info "Showing first $MAX_CIRCULAR_FILES_PER_OUTPUT of $chains circular dependencies:"
                echo "$filtered_circular" | head -$MAX_CIRCULAR_FILES_PER_OUTPUT | sed 's/^/    /'
                
                # Create filename with suffix
                local file_base=$(basename "$file" | sed 's/\.[^.]*$//')
                local output_file="circular-deps-${file_base}-$(date +%Y%m%d-%H%M%S).txt"
                
                echo ""
                print_warning "⚠️  Found $chains circular dependencies in $file (showing first $MAX_CIRCULAR_FILES_PER_OUTPUT)"
                print_info "All circular dependencies for $file saved to: $output_file"
                
                # Save all dependencies to file
                {
                    echo "Circular Dependencies Report for: $file"
                    echo "Generated: $(date)"
                    echo "Repository: $(git rev-parse --show-toplevel 2>/dev/null || pwd)"
                    echo "Branch: $(git branch --show-current 2>/dev/null || 'unknown')"
                    echo "Total circular dependencies found: $chains"
                    echo ""
                    echo "=== CIRCULAR DEPENDENCIES ==="
                    echo ""
                    echo "$filtered_circular"
                } > "$output_file"
            fi
            echo ""
        else
            print_success "No circular dependencies involving $file"
        fi
    else
        print_success "No circular dependencies in $file"
    fi
}

# Function to analyze all files for circular dependencies
analyze_files() {
    local js_ts_files="$1"
    
    print_info_must "Checking for circular dependencies..."
    echo ""
    
    while IFS= read -r file; do
        analyze_file "$file"
    done <<< "$js_ts_files"
}

# Function to print summary and exit with appropriate code
print_summary_and_exit() {
    echo ""
    print_info_must "=== SUMMARY ==="
    print_info_must "Total files analyzed: $TOTAL_FILES"
    print_info_must "Files with circular dependencies: $FILES_WITH_CIRCULAR_DEPS"
    print_info_must "Total circular dependency chains found: $CIRCULAR_DEPS_FOUND"
    
    if [ $FILES_WITH_CIRCULAR_DEPS -gt 0 ]; then
        echo ""
        print_error "❌ Circular dependencies detected!"
        print_info_must "Consider refactoring the affected files to remove circular dependencies."
        print_info_must "Circular dependencies can cause issues with bundling, testing, and runtime behavior."
        exit 1
    else
        echo ""
        print_success_must "✅ No circular dependencies found in changed files!"
        exit 0
    fi
}

# Main function
main() {
    parse_args "$@"
    
    check_git_repo
    check_dependencies
    
    local base_branch
    base_branch=$(get_base_branch)
    
    local changed_files
    if ! changed_files=$(get_changed_files "$base_branch"); then
        exit 0
    fi

    
    local js_ts_files
    if ! js_ts_files=$(filter_js_ts_files "$changed_files"); then
        exit 0
    fi
    
    analyze_files "$js_ts_files"
    
    print_summary_and_exit
}

# Run the main function
main "$@"
