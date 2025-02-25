# Project paths
export DOORLOOP_PATH="$HOME/WebstormProjects/doorloop"
export SERVER_PATH="$DOORLOOP_PATH/server"


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

servertest() {
    DYNAMIC_TEST_PATH="**/*.test.ts"

    if [ ! -z "$1" ]; then
        DYNAMIC_TEST_PATH="**/*$1*.test.ts"
    fi

    CMD="NODE_OPTIONS=--max-old-space-size=65536 node $DOORLOOP_PATH/node_modules/jest/bin/jest.js -c $SERVER_PATH/jest.config.js --runInBand $DYNAMIC_TEST_PATH"
    
    cd $SERVER_PATH
    echo $CMD
    eval $CMD
}
