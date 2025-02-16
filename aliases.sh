alias stricttoggle="sed -e 's/\"strictNullChecks\": true/\"strictNullChecks\": false/;s/\"strictNullChecks\": false/\"strictNullChecks\": true/' server/tsconfig.json > server/tsconfig.json.tmp && mv server/tsconfig.json.tmp server/tsconfig.json"
alias stricton="sed -i '' 's/\"strictNullChecks\": false/\"strictNullChecks\": true/' server/tsconfig.json"
alias strictoff="sed -i '' 's/\"strictNullChecks\": true/\"strictNullChecks\": false/' server/tsconfig.json"

alias val="strictoff && pnpm run build:packages && (pnpm run type-check & pnpm run lint & pnpm run format:check) && wait && stricton"
alias valfull="pnpm i && pnpm run build-prod && (strictoff && pnpm run type-check-strict && stricton)"

alias aicli="gh copilot suggest"
alias switchbranch="pnpm i && pnpm run build-dev"
alias git-search='f() { git branch --format="%(refname:short)" | xargs -I {} git grep "$1" {}; }; f'

alias test="cd /Users/neriyarosner/WebstormProjects/doorloop/server && NODE_OPTIONS=--max-old-space-size=65536 node /Users/neriyarosner/WebstormProjects/doorloop/node_modules/jest/bin/jest.js -c /Users/neriyarosner/WebstormProjects/doorloop/server/jest.config.js --runInBand"