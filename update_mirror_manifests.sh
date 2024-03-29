#!/bin/bash

set -e

[[ -f ./config.conf ]] || exit 1
#shellcheck disable=SC1091
source ./config.conf

bucket_dir="$mirror_manifests_dir/bucket"

for dir in $repos_dir $bucket_dir $files_dir; do
    [[ -d $dir ]] || mkdir -p "$dir"
done

declare manifest_file manifest_name app_version app_version_old url local_url local_file i sync_text="" hashsums=() repo_name line

#shellcheck disable=SC2016
sync_text+='#!/bin/bash

function check_hash() {
    if [[ $1 =~ sha1: ]]; then
        echo "${1//sha1\:/} $2" | sha1sum -c - &>> /dev/null
        return $?
    elif [[ $1 =~ sha512: ]]; then
        echo "${1//sha512\:/} $2" | sha512sum -c - &>> /dev/null
        return $?
    elif [[ $1 =~ md5: ]]; then
        echo "${1//md5\:/} $2" | md5sum -c - &>> /dev/null
        return $?
    else
        echo "$1 $2" | sha256sum -c - &>> /dev/null
        return $?
    fi
}

function down_check() {
    if check_hash "$1" "$2"; then
        echo "+++File $2 is correct!"
    else
        if [[ -n "$2" ]]; then
            echo "---Incorrect hash of $2! Removing and trying again..."
            rm -rf "${2:?}"
        fi
        if wget -c -O "$2" "$3"; then
            echo "+++Downloaded file $2."
        else
            echo "---Failed to download $2! Skipping..."
        fi
    fi
}

'

while IFS=" " read -r -a repo_name; do
    repo="${repo_name[0]}"
    name="$repos_dir/${repo_name[1]}"
    if [[ -d "$name/.git" ]]; then
        git -C "$name" pull origin --rebase
    else
        mkdir -p "$name"
        git clone "$repo" "$name"
    fi
done <<<"$repos"

while read -r -a line; do
    manifest_file="${line[0]}"
    manifest_name="${line[1]}"
    manifest="$(<"$repos_dir/$manifest_file")"
    #shellcheck disable=SC2001
    app_version="$(yq --raw-output '.version' <<< "$manifest")"
    app_version_old=0
    if [[ -f "$bucket_dir/$manifest_name.json" ]]; then
        app_version_old="$(yq --raw-output '.version' < "$bucket_dir/$manifest_name.json")"
    fi
    sync_text+="mkdir -p '$files_dir/$manifest_name/$app_version'\n"
    # Take list of hashes to array hashsums.
    hashsums=()
    while read -r hash; do
        hashsums=("${hashsums[@]}" "$hash")
    done <<< "$(<<< "$manifest" \
        yq --raw-output 'if (.architecture != null) and (.architecture[.architecture | keys[0]].hash != null) then .architecture[].hash else .hash end | if type == "array" then .[] else . end')"
    i=$((0))
    # Get urls with hashes from array hashsums and add them to sync_text variable. In if block we detect how to save file: with its original name or name from manifest.
    while read -r url; do
        if [[ $url =~ \#\/([0-9a-zA-Z.\-]+)$ ]]; then
            local_file="$manifest_name/$app_version/${i}_${BASH_REMATCH[1]}" local_url="${url//#\/${BASH_REMATCH[1]}/}" name_file=${BASH_REMATCH[1]}
            manifest="${manifest//$url/$mirror_prefix/$local_file#/$name_file}"
        else
            [[ $url =~ \/([0-9a-zA-Z.\_\-]+)$ ]] && local_file="$manifest_name/$app_version/${i}_${BASH_REMATCH[1]}" local_url="${url}"
            manifest="${manifest//$url/$mirror_prefix/$local_file}"
        fi
        sync_text+="down_check '${hashsums[i]}' '$files_dir/$local_file' '$local_url'\n"
        : $((i++))
    done <<< "$(<<< "$manifest" \
        yq --raw-output 'if (.architecture != null) and (.architecture[.architecture | keys[0]].url != null) then .architecture[].url else .url end | if type == "array" then .[] else . end')"
    # Match manifests.
    if [[ -f "$bucket_dir/$manifest_name.json" ]]; then
        if [[ "$manifest" != "$(< "$bucket_dir/$manifest_name.json")" ]]; then
            if [[ $app_version_old != "0" ]]; then
                echo "Updating manifest for $manifest_name..."
                sync_text+="rm -rf '$files_dir/$manifest_name/$app_version_old'\n"
                echo -n "$manifest" > "$bucket_dir/$manifest_name.json"
            fi
            echo -n "$manifest" > "$bucket_dir/$manifest_name.json"
        else
            echo "Keeping manifest for $manifest_name..."
        fi
    else
        echo "Creating manifest for $manifest_name..."
        echo -n "$manifest" > "$bucket_dir/$manifest_name.json"
    fi
done <<< "$manifests"

echo -ne "$sync_text" > "$sync_file"
chmod +x "$sync_file"

if [[ $use_git == "1" ]]; then
    cd "$mirror_manifests_dir"
    [[ -d .git ]] || git init -b master
    git add \*
    git commit -m "Updated on \"$(date)\"." || :
fi
