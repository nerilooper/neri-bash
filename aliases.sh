# Initialize development environment
init_dev_env() {
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                   # This loads nvm
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" # This loads nvm bash_completion

    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
}

# Set up project paths
setup_project_paths() {
    # Project paths
    if [[ "$(pwd)" == *"/apps/server"* ]]; then
        export DOORLOOP_PATH="$(dirname "$(dirname "$(pwd)")")"
    else
        export DOORLOOP_PATH=$(pwd)
    fi

    export SERVER_PATH="$DOORLOOP_PATH/apps/server"
    export CLIENT_PATH="$DOORLOOP_PATH/apps/client"
}

# Create TypeScript strict mode aliases
setup_strict_aliases() {
    alias stricttoggle="sed -e 's/\"strictNullChecks\": true/\"strictNullChecks\": false/;s/\"strictNullChecks\": false/\"strictNullChecks\": true/' $SERVER_PATH/tsconfig.json > $SERVER_PATH/tsconfig.json.tmp && mv $SERVER_PATH/tsconfig.json.tmp $SERVER_PATH/tsconfig.json"
    alias stricton="sed -i '' 's/\"strictNullChecks\": false/\"strictNullChecks\": true/' $SERVER_PATH/tsconfig.json"
    alias strictoff="sed -i '' 's/\"strictNullChecks\": true/\"strictNullChecks\": false/' $SERVER_PATH/tsconfig.json"
}

# Create validation aliases
setup_validation_aliases() {
    alias val="strictoff && pnpm run build:packages && (pnpm run type-check & pnpm run lint & pnpm run format:check) && wait && stricton"
    alias valfull="pnpm i && pnpm run build-prod && (strictoff && pnpm run type-check-strict && stricton)"
}

# Create general utility aliases
setup_utility_aliases() {
    alias aicli="gh copilot suggest"
    alias switchbranch="pnpm i && pnpm run build-dev"
    alias git-search='f() { git branch --format="%(refname:short)" | xargs -I {} git grep "$1" {}; }; f'
    alias editrc="cursor ~/.zshrc"
    alias editbash="cursor ~/.bashrc"
    alias editprofile="cursor ~/.zprofile"
    alias pullall="git fetch --all && git pull --all"
}

# Create development-specific aliases
setup_dev_aliases() {
    alias storybook="cd $CLIENT_PATH && pnpm run storybook"
    alias docker-debug="pnpm docker-bootstrap 651d09f9a3895d22c843074a && USE_DOCKER=true pnpm debug-dev"
}

# Server test function
servertest() {
    TEST_PATH_PATTERN=""
    TEST_NAME_FILTER=""
    TARGET_PATH="$SERVER_PATH"
    JEST_CONFIG="$SERVER_PATH/jest.config.ts"
    NODE_MODULES_PATH="$DOORLOOP_PATH/node_modules"
    NODE_OPTIONS="--max-old-space-size=65536 --experimental-vm-modules"

    # Check for --lib flag
    if [ "$1" = "--lib" ]; then
        if [ -z "$2" ]; then
            echo "Usage: servertest --lib <libname> [test-file-filter] [test-name-filter]"
            return 1
        fi
        LIB_NAME="$2"
        TARGET_PATH="$DOORLOOP_PATH/libs/$LIB_NAME"
        JEST_CONFIG="$TARGET_PATH/jest.config.ts"
        shift 2
        # Now $1 is test-file-filter, $2 is test-name-filter
        if [ ! -z "$1" ]; then
            TEST_PATH_PATTERN="--testPathPattern=\".*$1.*\.test\.ts$\""
        fi
        if [ ! -z "$2" ]; then
            TEST_NAME_FILTER="-t \"$2\""
        fi
    else
        # First arg filters test files
        if [ ! -z "$1" ]; then
            TEST_PATH_PATTERN="--testPathPattern=\".*$1.*\.test\.ts$\""
        fi
        # Second arg filters by test name
        if [ ! -z "$2" ]; then
            TEST_NAME_FILTER="-t \"$2\""
        fi
    fi

    CMD="NODE_OPTIONS=\"$NODE_OPTIONS\" node $NODE_MODULES_PATH/jest/bin/jest.js -c $JEST_CONFIG --runInBand $TEST_PATH_PATTERN $TEST_NAME_FILTER"

    cd $TARGET_PATH
    echo $CMD
    eval $CMD
    cd $DOORLOOP_PATH
}


# Client test function
clienttest() {
    TEST_PATH_PATTERN=""
    TEST_NAME_FILTER=""
    EXTRA_ARGS=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --watch|-w)
                EXTRA_ARGS="$EXTRA_ARGS --watch"
                shift
                ;;
            --coverage)
                EXTRA_ARGS="$EXTRA_ARGS --coverage"
                shift
                ;;
            --ui)
                EXTRA_ARGS="$EXTRA_ARGS --ui"
                shift
                ;;
            -t|--testNamePattern)
                if [ ! -z "$2" ]; then
                    TEST_NAME_FILTER="-t \"$2\""
                    shift 2
                else
                    echo "Error: --testNamePattern requires a value"
                    return 1
                fi
                ;;
            *)
                # First non-flag argument is test file filter
                if [ -z "$TEST_PATH_PATTERN" ]; then
                    TEST_PATH_PATTERN="$1"
                # Second non-flag argument is test name filter (if -t wasn't used)
                elif [ -z "$TEST_NAME_FILTER" ]; then
                    TEST_NAME_FILTER="-t \"$1\""
                fi
                shift
                ;;
        esac
    done

    # Build the command
    CMD="nx run client:test"
    
    # Add test file pattern if specified
    if [ ! -z "$TEST_PATH_PATTERN" ]; then
        CMD="$CMD $TEST_PATH_PATTERN"
    fi
    
    # Add test name filter if specified
    if [ ! -z "$TEST_NAME_FILTER" ]; then
        CMD="$CMD $TEST_NAME_FILTER"
    fi
    
    # Add extra arguments
    if [ ! -z "$EXTRA_ARGS" ]; then
        CMD="$CMD $EXTRA_ARGS"
    fi

    echo "Running: $CMD"
    eval $CMD
}

# TypeScript single file type check function
typecheck_file() {
    if [ -z "$1" ]; then
        echo "Usage: typecheck_file <filepath>"
        echo "Example: typecheck_file apps/server/src/api/capital/capital.controller.ts"
        return 1
    fi

    local filepath="$1"
    local temp_config="temp-typecheck.json"

    # Check if file exists
    if [ ! -f "$filepath" ]; then
        echo "Error: File '$filepath' not found"
        return 1
    fi

    # Determine if it's a test file or application file
    local config_extends
    if [[ "$filepath" == *".test.ts" ]] || [[ "$filepath" == *".spec.ts" ]] || [[ "$filepath" == *"__tests__"* ]] || [[ "$filepath" == *"jest.config.ts" ]]; then
        config_extends="./apps/server/tsconfig.spec.json"
        echo "Type-checking test file: $filepath"
    else
        config_extends="./apps/server/tsconfig.app.json"
        echo "Type-checking application file: $filepath"
    fi

    # Create temporary config file
    echo "{\"extends\":\"$config_extends\",\"include\":[\"$filepath\", \"**/*.d.ts\"]}" >"$temp_config"

    # Run TypeScript compiler and filter output
    echo "Running TypeScript compiler..."
    local result=$(npx tsc --noEmit -p "$temp_config" 2>&1 | grep "$filepath")

    # Clean up temporary file
    rm "$temp_config"

    # Display results
    if [ -z "$result" ]; then
        echo "✅ No type errors found in $filepath"
    else
        echo "❌ Type errors found:"
        echo "$result"
    fi
}

# Initialize all configurations
init_dev_env
setup_project_paths
setup_strict_aliases
setup_validation_aliases
setup_utility_aliases
setup_dev_aliases
