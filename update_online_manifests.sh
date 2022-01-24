#!/bin/bash

set -e

[[ -f ./config.conf ]] || exit 1
#shellcheck disable=SC1091
source ./config.conf

for dir in $online_manifests_dir $repos_dir; do
    [[ -d $dir ]] || mkdir -p "$dir"
done


function git_update() {
    IFS=" " read -r -a repo_name <<< "$*"
    repo="${repo_name[0]}"
    name="${repo_name[1]}"
    echo " [Git update $name to $name...]"
    if [[ -d "$name/.git" ]]; then
        git -C "$name" pull origin --rebase || echo "Failed to update $name!"
    else
        mkdir -p "$name"
        git clone "$repo" "$name" || echo "Failed to create $name!"
    fi
}

while IFS= read -r repo_name; do
    git_update "$repo_name"
done <<<"$repos"

while IFS= read -r manifest; do
    cmp -s -- "$repos_dir/$manifest" "$online_manifests_dir/$(basename "$manifest")" \
        || cp "$repos_dir/$manifest" "$online_manifests_dir/$(basename "$manifest")"
done <<<"$manifests"