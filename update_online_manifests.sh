#!/bin/bash

set -e

online_manifests_dir="online_manifests"
bucket_dir="buckets"
repos="https://github.com/ScoopInstaller/Main.git $bucket_dir/main
https://github.com/ScoopInstaller/Extras.git $bucket_dir/extras
https://github.com/ScoopInstaller/Java.git $bucket_dir/java
https://github.com/alealexpro100/ru-school-scoop.git $bucket_dir/ru-school-scoop"

manifests="extras/bucket/audacity.json
extras/bucket/blender.json
extras/bucket/codeblocks-mingw.json
extras/bucket/firefox.json
extras/bucket/gimp.json
extras/bucket/idea.json
extras/bucket/inkscape.json
extras/bucket/lazarus.json
extras/bucket/libreoffice-stable.json
extras/bucket/notepadplusplus.json
java/bucket/oraclejre8.json
extras/bucket/pycharm.json
extras/bucket/scratch.json"

for dir in $online_manifests_dir $bucket_dir; do
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
    cmp -s -- "$bucket_dir/$manifest" "$online_manifests_dir/$(basename "$manifest")" \
        || cp "$bucket_dir/$manifest" "$online_manifests_dir/$(basename "$manifest")"
done <<<"$manifests"