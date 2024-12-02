alias val="pnpm run build-dev && pnpm run type-check"
alias valfull="pnpm i && val && pnpm run type-check-strict"

alias aicli="gh copilot suggest"
alias switchbranch="pnpm i && pnpm run build-dev"
alias git-search='f() { git branch --format="%(refname:short)" | xargs -I {} git grep "$1" {}; }; f'