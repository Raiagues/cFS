#!/bin/bash

USERNAME="Raiagues"

ROOT_DIR=$(pwd)

echo "========================================="
echo "Recreating repositories"
echo "========================================="

TARGETS=(
"."
"./apps/cs"
"./apps/fm"
"./apps/ds"
"./apps/md"
"./apps/sbn"
"./apps/hk"
"./apps/lc"
"./apps/mm"
"./apps/ci_lab"
"./apps/cf"
"./apps/sc"
"./apps/to_lab"
"./apps/sch_lab"
"./apps/hs"
"./apps/sample_app"
"./osal"
"./cfe"
"./psp"
"./libs/sample_lib"
"./tools/tblCRCTool"
"./tools/cfs-cosmos-plugin"
"./tools/commandline-tools"
"./tools/elf2cfetbl"
"./tools/cFS-GroundSystem"
"./tools/eds"
)

for repo_path in "${TARGETS[@]}"; do

    echo ""
    echo "-----------------------------------------"
    echo "Processing: $repo_path"

    cd "$ROOT_DIR/$repo_path" || continue

    rm -rf .git

    git init

    git add .

    git commit -m "Initial commit"

    repo_name=$(echo "$repo_path" | \
        sed 's|^\./||' | \
        sed 's|/|-|g')

    if [ "$repo_name" = "." ]; then
        repo_name="cFS"
    fi

    echo "Creating repo: $repo_name"

    gh repo create "$USERNAME/$repo_name" \
        --private \
        --source=. \
        --remote=origin \
        --push

done

echo ""
echo "========================================="
echo "DONE"
echo "========================================="
