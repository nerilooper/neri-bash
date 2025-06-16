#!/bin/bash

# Script to check for circular dependencies in files changed in the current PR
# Requires: git, madge (npm install -g madge)

set -e # Exit on any error

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

# Base branch override
BASE_BRANCH_OVERRIDE=""

# Save flag
SAVE_FILES=false

# Specific file override
SPECIFIC_FILE=""

# Exclude pattern
EXCLUDE_PATTERN=""

# Function to display help message
show_help() {
    echo "Usage: $0 [--verbose|-v] [--base BRANCH] [--save|-s] [--file FILE] [--exclude PATTERN] [--help|-h]"
    echo ""
    echo "Options:"
    echo "  --verbose, -v      Show detailed output including info and success messages"
    echo "  --base BRANCH      Specify the base branch to compare against (overrides auto-detection)"
    echo "  --save, -s         Save detailed circular dependency reports to files"
    echo "  --file FILE        Analyze a specific file instead of PR changed files"
    echo "  --exclude PATTERN  Exclude files matching the glob pattern (shown in red)"
    echo "  --help, -h         Show this help message"
    echo ""
    echo "By default, only errors and warnings are shown."
    echo "The base branch is auto-detected from GitHub PR or falls back to origin/main."
    echo "When --file is used, the base branch comparison is skipped."
    echo ""
    echo "Examples:"
    echo "  $0 --exclude '*.test.js'     # Exclude test files"
    echo "  $0 --exclude 'src/legacy/*'  # Exclude legacy directory"
}

# Function to validate file path and convert to absolute path
get_absolute_path() {
    local file="$1"
    local full_path

    # Convert relative path to absolute path if needed
    if [[ "$file" = /* ]]; then
        full_path="$file"
    else
        full_path="$(pwd)/$file"
    fi

    echo "$full_path"
}

# Function to check if file exists
validate_file_exists() {
    local file="$1"
    local full_path
    full_path=$(get_absolute_path "$file")

    if [ ! -f "$full_path" ]; then
        print_warning "File not found: $file (may have been deleted)" >&2
        return 1
    fi

    return 0
}

# Function to parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        --verbose | -v)
            VERBOSE=true
            shift
            ;;
        --base)
            if [[ -z "$2" || "$2" == --* ]]; then
                echo "Error: --base requires a branch name"
                exit 1
            fi
            BASE_BRANCH_OVERRIDE="$2"
            shift 2
            ;;
        --save | -s)
            SAVE_FILES=true
            shift
            ;;
        --file)
            if [[ -z "$2" || "$2" == --* ]]; then
                echo "Error: --file requires a file name"
                exit 1
            fi
            SPECIFIC_FILE="$2"
            shift 2
            ;;
        --exclude)
            if [[ -z "$2" || "$2" == --* ]]; then
                echo "Error: --exclude requires a pattern"
                exit 1
            fi
            EXCLUDE_PATTERN="$2"
            shift 2
            ;;
        --help | -h)
            show_help
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
        echo -e "${BLUE}[INFO]${NC} $1" >&2
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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        print_error "Not in a git repository. Please run this script from within a git repository."
        exit 1
    fi

    local repo_root
    repo_root=$(git rev-parse --show-toplevel)
    print_info_must "Git repository root: $repo_root"

}

# Function to check if madge is installed
check_dependencies() {
    if ! command -v madge &>/dev/null; then
        print_error "madge is not installed. Please install it with: npm install -g madge"
        exit 1
    fi
}

# Function to get the base branch
get_base_branch() {
    local base_branch=""

    # Try to get base branch from GitHub PR first
    if command -v gh &>/dev/null; then
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

# Function to display branch information
display_branch_info() {
    local base_branch="$1"
    local current_branch
    current_branch=$(git branch --show-current)

    print_info_must "Current branch: $current_branch"
    print_info_must "Base branch: $base_branch"
    print_info "Git diff command: git diff --name-only $base_branch...HEAD"
    echo "" >&2
    print_info_must "Files changed in current PR:"
}

# Function to handle no changed files scenario
handle_no_changed_files() {
    local current_branch="$1"
    local base_branch="$2"

    print_warning "No files changed between $current_branch and $base_branch"
    print_info "This usually means:"
    print_info "  - You're on the base branch ($base_branch) with no new commits"
    print_info "  - Your branch is up to date with the base branch"
    print_info "  - There are no committed changes in your branch"
}

# Function to get changed files in the current PR
get_changed_files() {
    local base_branch="$1"
    local current_branch
    current_branch=$(git branch --show-current)

    display_branch_info "$base_branch"

    local changed_files
    changed_files=$(git diff --name-only "$base_branch"...HEAD)

    if [ -z "$changed_files" ]; then
        handle_no_changed_files "$current_branch" "$base_branch"
        return 1
    fi

    print_info "Found $(echo "$changed_files" | wc -l | tr -d ' ') changed files in PR ($current_branch vs $base_branch)" >&2

    echo "$changed_files"
}

# Function to check if a file matches the exclude pattern
file_matches_exclude_pattern() {
    local file="$1"
    local pattern="$2"

    if [ -z "$pattern" ]; then
        return 1 # No pattern means no match
    fi

    # Use bash's built-in pattern matching
    if [[ "$file" == $pattern ]]; then
        return 0 # Match found
    fi

    return 1 # No match
}

# Function to display file with appropriate color
display_file_status() {
    local file="$1"
    local is_excluded="$2"

    if [ "$is_excluded" = "true" ]; then
        echo -e "  - ${RED}$file (excluded)${NC}" >&2
    else
        echo "  - $file" >&2
    fi
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

    local files_to_analyze=""
    local excluded_count=0
    local total_count=0

    # First pass: collect files and count exclusions
    while IFS= read -r file; do
        if [ -n "$file" ]; then
            total_count=$((total_count + 1))

            if file_matches_exclude_pattern "$file" "$EXCLUDE_PATTERN"; then
                excluded_count=$((excluded_count + 1))
            else
                if [ -z "$files_to_analyze" ]; then
                    files_to_analyze="$file"
                else
                    files_to_analyze="$files_to_analyze"$'\n'"$file"
                fi
            fi
        fi
    done <<<"$js_ts_files"

    # Display the files with proper formatting
    print_info "JavaScript/TypeScript files found:"
    while IFS= read -r file; do
        if [ -n "$file" ]; then
            if file_matches_exclude_pattern "$file" "$EXCLUDE_PATTERN"; then
                display_file_status "$file" "true"
            else
                display_file_status "$file" "false"
            fi
        fi
    done <<<"$js_ts_files"

    echo "" >&2

    if [ -n "$EXCLUDE_PATTERN" ]; then
        print_info_must "Excluded $excluded_count of $total_count files matching pattern: $EXCLUDE_PATTERN"
        echo "" >&2
    fi

    if [ -z "$files_to_analyze" ]; then
        print_warning "No JavaScript/TypeScript files to analyze after applying exclusions"
        return 1
    fi

    echo "$files_to_analyze"
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
    done <<<"$circular_output"

    echo "$filtered_circular"
}

# Function to run madge analysis on a file
run_madge_analysis() {
    local full_path="$1"
    madge --circular "$full_path" 2>/dev/null || true
}

# Function to count circular dependency chains
count_circular_chains() {
    local filtered_circular="$1"
    echo "$filtered_circular" | grep -c ">" || true
}

# Function to display circular dependencies
display_circular_dependencies() {
    local file="$1"
    local filtered_circular="$2"
    local chains="$3"

    print_error "Circular dependencies involving $file:"

    local MAX_CIRCULAR_FILES_PER_OUTPUT=5

    if [ $chains -le $MAX_CIRCULAR_FILES_PER_OUTPUT ]; then
        # Show all if MAX_CIRCULAR_FILES_PER_OUTPUT or fewer
        echo "$filtered_circular" | sed 's/^/    /'
    else
        # Show first MAX_CIRCULAR_FILES_PER_OUTPUT
        print_info "Showing first $MAX_CIRCULAR_FILES_PER_OUTPUT of $chains circular dependencies:"
        echo "$filtered_circular" | head -$MAX_CIRCULAR_FILES_PER_OUTPUT | sed 's/^/    /'

        echo ""
        print_warning "⚠️  Found $chains circular dependencies in $file (showing first $MAX_CIRCULAR_FILES_PER_OUTPUT)"

        if [ "$SAVE_FILES" = false ]; then
            print_info "Use --save flag to save all circular dependencies to a file"
        fi
    fi
}

# Function to save circular dependencies to file
save_circular_dependencies_to_file() {
    local file="$1"
    local filtered_circular="$2"
    local chains="$3"

    # Create filename with suffix
    local file_base=$(basename "$file" | sed 's/\.[^.]*$//')
    local output_file="circular-deps-${file_base}-$(date +%Y%m%d-%H%M%S).txt"

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
    } >"$output_file"
}

# Function to process circular dependencies found in a file
process_circular_dependencies() {
    local file="$1"
    local filtered_circular="$2"

    if [ -n "$filtered_circular" ]; then
        FILES_WITH_CIRCULAR_DEPS=$((FILES_WITH_CIRCULAR_DEPS + 1))

        # Count the number of circular dependency chains
        local chains
        chains=$(count_circular_chains "$filtered_circular")
        CIRCULAR_DEPS_FOUND=$((CIRCULAR_DEPS_FOUND + chains))

        display_circular_dependencies "$file" "$filtered_circular" "$chains"

        # Save to file if --save flag is used
        if [ "$SAVE_FILES" = true ]; then
            save_circular_dependencies_to_file "$file" "$filtered_circular" "$chains"
        fi
        echo ""
    else
        print_success "No circular dependencies involving $file"
    fi
}

# Function to analyze a single file for circular dependencies
analyze_file() {
    local file="$1"

    if ! validate_file_exists "$file"; then
        return
    fi

    local full_path
    full_path=$(get_absolute_path "$file")

    TOTAL_FILES=$((TOTAL_FILES + 1))
    print_info "Analyzing: $file"

    # Run madge to check for circular dependencies using the full path
    local circular_output
    circular_output=$(run_madge_analysis "$full_path")

    if [ -n "$circular_output" ]; then
        local filtered_circular
        filtered_circular=$(filter_circular_deps_for_file "$file" "$circular_output")
        process_circular_dependencies "$file" "$filtered_circular"
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
    done <<<"$js_ts_files"
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

# Function to determine the base branch to use
determine_base_branch() {
    local base_branch
    if [ -n "$BASE_BRANCH_OVERRIDE" ]; then
        base_branch="$BASE_BRANCH_OVERRIDE"
        print_info_must "Using specified base branch: $base_branch"
    else
        base_branch=$(get_base_branch)
    fi
    echo "$base_branch"
}

# Function to perform initial setup and validation
setup_and_validate() {
    # Always check for madge dependency
    check_dependencies

    # Only check git repo if we're not analyzing a specific file
    if [ -z "$SPECIFIC_FILE" ]; then
        check_git_repo
    fi
}

# Function to validate specific file is JavaScript/TypeScript
validate_js_ts_file() {
    local file="$1"

    if ! echo "$file" | grep -qE '\.(js|jsx|ts|tsx|mjs|cjs)$'; then
        print_error "File '$file' is not a JavaScript/TypeScript file"
        print_info_must "Supported extensions: .js, .jsx, .ts, .tsx, .mjs, .cjs"
        return 1
    fi

    return 0
}

# Function to get files to analyze from PR
get_files_from_pr() {
    local base_branch="$1"

    local changed_files
    if ! changed_files=$(get_changed_files "$base_branch"); then
        return 1
    fi

    local js_ts_files
    if ! js_ts_files=$(filter_js_ts_files "$changed_files"); then
        return 1
    fi

    echo "$js_ts_files"
}

# Function to get files to analyze (either specific file or from PR)
get_files_to_analyze() {
    local base_branch="$1"

    if [ -n "$SPECIFIC_FILE" ]; then
        print_info_must "Analyzing specific file: $SPECIFIC_FILE"

        if ! validate_file_exists "$SPECIFIC_FILE"; then
            return 1
        fi

        if ! validate_js_ts_file "$SPECIFIC_FILE"; then
            return 1
        fi

        echo "$SPECIFIC_FILE"
    else
        get_files_from_pr "$base_branch"
    fi
}

# Main function
main() {
    parse_args "$@"

    setup_and_validate

    local base_branch=""
    local js_ts_files

    if [ -n "$SPECIFIC_FILE" ]; then
        # When analyzing a specific file, we don't need base branch
        if ! js_ts_files=$(get_files_to_analyze ""); then
            exit 1
        fi
    else
        # When analyzing PR files, we need base branch
        base_branch=$(determine_base_branch)
        if ! js_ts_files=$(get_files_to_analyze "$base_branch"); then
            exit 0
        fi
    fi

    analyze_files "$js_ts_files"

    print_summary_and_exit
}

# Run the main function
main "$@"
