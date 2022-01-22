#!/bin/bash

set -e

[[ -f ./config.conf ]] || exit 1
#shellcheck disable=SC1091
source ./config.conf

if [[ ! -d $online_manifests_dir ]]; then
    echo "Directory '$online_manifests_dir' not found!"
    exit 1
fi

for dir in $mirror_manifests_dir $files_dir; do
    [[ -d $dir ]] || mkdir -p "$dir"
done

declare manifest_file app_name app_version app_version_old url i sync_text=""

while read -r manifest_file; do
    manifest="$(<"$online_manifests_dir/$manifest_file")"
    #shellcheck disable=SC2001
    app_name="$(<<<"$manifest_file" sed -e 's|.\w\+$||')"
    app_version="$(jq --raw-output '.version' <<< "$manifest")"
    if [[ -f "$mirror_manifests_dir/$app_name.json" ]]; then
        app_version_old="$(jq --raw-output '.version' < "$mirror_manifests_dir/$app_name.json")"
    else
        app_version_old=0
    fi
    sync_text+="mkdir -p '$files_dir/$app_name/$app_version'\n"
    i=$((0))
    while read -r url; do
        : $((i++))
        if [[ $url =~ \#\/([0-9a-zA-Z.]+)$ ]]; then
            sync_text+="wget -O '$files_dir/$app_name/$app_version/${i}_${BASH_REMATCH[1]}' -c '$(<<<"$url" sed -e "s|\#\/||;s|${BASH_REMATCH[1]}||")'\n"
        else
            [[ $url =~ \/([0-9a-zA-Z.\_\-]+)$ ]] && sync_text+="wget -O '$files_dir/$app_name/$app_version/${i}_${BASH_REMATCH[1]}' -c '${url}'\n"
        fi
        manifest="${manifest//$url/$mirror_prefix/$app_name/$app_version/${i}_${BASH_REMATCH[1]}}"
    done <<< "$(<<< "$manifest" \
        jq --raw-output 'if .architecture != null then (if (.architecture[].url | type == "array") then (.architecture[].url | join("\n")) else .architecture[].url end) else null end + .url' \
        | sort -u)"
    if [[ $app_version != "$app_version_old" ]]; then
        if [[ $app_version_old != "0" ]]; then
            echo "Updating manifest for $app_name..."
            sync_text+="rm -rf '$files_dir/$app_name/$app_version_old'\n"
        else
            echo "Creating manifest for $app_name..."
        fi
        #shellcheck disable=SC2001
        <<<"$manifest" sed -e 's|\n|\r\n|g' > "$mirror_manifests_dir/$app_name.json"
    else
        echo "Keeping manifest for $app_name..."
    fi
done <<< "$(find $online_manifests_dir/ | sed -e 's|^\(\w\+\)/||;/^$/d')"

echo -ne "$sync_text" > "$sync_file"
chmod +x "$sync_file"

if [[ $use_git == "1" ]]; then
    cd "$mirror_manifests_dir"
    [[ -d .git ]] || git init
    git add \*
    git commit -m "Updated on \"$(date)\"." || :
fi