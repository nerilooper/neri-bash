# Project paths
if [[ "$(pwd)" == *"/server"* ]]; then
    export SERVER_PATH=$(pwd)
    export DOORLOOP_PATH="$(dirname "$SERVER_PATH")"
else
    export DOORLOOP_PATH=$(pwd)
    export SERVER_PATH="$DOORLOOP_PATH/apps/server"
fi

export CLIENT_PATH="$DOORLOOP_PATH/apps/client"

alias stricttoggle="sed -e 's/\"strictNullChecks\": true/\"strictNullChecks\": false/;s/\"strictNullChecks\": false/\"strictNullChecks\": true/' $SERVER_PATH/tsconfig.json > $SERVER_PATH/tsconfig.json.tmp && mv $SERVER_PATH/tsconfig.json.tmp $SERVER_PATH/tsconfig.json"
alias stricton="sed -i '' 's/\"strictNullChecks\": false/\"strictNullChecks\": true/' $SERVER_PATH/tsconfig.json"
alias strictoff="sed -i '' 's/\"strictNullChecks\": true/\"strictNullChecks\": false/' $SERVER_PATH/tsconfig.json"

alias val="strictoff && pnpm run build:packages && (pnpm run type-check & pnpm run lint & pnpm run format:check) && wait && stricton"
alias valfull="pnpm i && pnpm run build-prod && (strictoff && pnpm run type-check-strict && stricton)"

alias aicli="gh copilot suggest"
alias switchbranch="pnpm i && pnpm run build-dev"
alias git-search='f() { git branch --format="%(refname:short)" | xargs -I {} git grep "$1" {}; }; f'

alias editrc="code ~/.zshrc"
alias pullall="git fetch --all && git pull --all"

alias storybook="cd $CLIENT_PATH && pnpm run storybook"

alias docker-debug="pnpm docker-bootstrap 651d09f9a3895d22c843074a && USE_DOCKER=true pnpm debug-dev"

servertest() {
    DYNAMIC_TEST_PATH="**/*.test.ts"
    TEST_NAME_FILTER=""
    TARGET_PATH="$SERVER_PATH"
    JEST_CONFIG="$SERVER_PATH/jest.config.ts"

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
            DYNAMIC_TEST_PATH="**/*$1*.test.ts"
        fi
        if [ ! -z "$2" ]; then
            TEST_NAME_FILTER="-t \"$2\""
        fi
    else
        # First arg filters test files
        if [ ! -z "$1" ]; then
            DYNAMIC_TEST_PATH="**/*$1*.test.ts"
        fi
        # Second arg filters by test name
        if [ ! -z "$2" ]; then
            TEST_NAME_FILTER="-t \"$2\""
        fi
    fi

    CMD="NODE_OPTIONS=\"--max-old-space-size=65536 --experimental-vm-modules\" node $DOORLOOP_PATH/node_modules/jest/bin/jest.js -c $JEST_CONFIG --runInBand $DYNAMIC_TEST_PATH $TEST_NAME_FILTER"

    cd $TARGET_PATH
    echo $CMD
    eval $CMD
    cd $DOORLOOP_PATH
}