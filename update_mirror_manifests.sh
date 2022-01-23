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

declare manifest_file app_name app_version app_version_old url local_url local_file i sync_text="" hashsums=()

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
        echo "---Incorrect hash of $2! Removing and trying again..."]
        rm -rf "${2:?}"
        if wget -c -O "$2" "$3"; then
            echo "+++Downloaded file $2."
        else
            echo "---Failed to download $2! Skipping..."
        fi
    fi
}

'

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
    # Take list of hashes to array hashsums.
    hashsums=()
    while read -r hash; do
        hashsums=("${hashsums[@]}" "$hash")
    done <<< "$(<<< "$manifest" \
        jq --raw-output 'if (.architecture != null) and (.architecture[.architecture | keys[0]].hash != null) then .architecture[].hash else .hash end | if type == "array" then .[] else . end')"
    i=$((0))
    # Get urls with hashes from array hashsums and add them to sync_text variable. In if block we detect how to save file: with its original name or name from manifest.
    while read -r url; do
        if [[ $url =~ \#\/([0-9a-zA-Z.]+)$ ]]; then
            local_file="$files_dir/$app_name/$app_version/${i}_${BASH_REMATCH[1]}" local_url="$(<<<"$url" sed -e "s|\#\/||;s|${BASH_REMATCH[1]}||")"
        else
            [[ $url =~ \/([0-9a-zA-Z.\_\-]+)$ ]] && local_file="$files_dir/$app_name/$app_version/${i}_${BASH_REMATCH[1]}" local_url="${url}"
        fi
        sync_text+="down_check '${hashsums[i]}' '$local_file' '$local_url'\n"
        manifest="${manifest//$url/$mirror_prefix/$app_name/$app_version/${i}_${BASH_REMATCH[1]}}"
        : $((i++))
    done <<< "$(<<< "$manifest" \
        jq --raw-output 'if (.architecture != null) and (.architecture[.architecture | keys[0]].url != null) then .architecture[].url else .url end | if type == "array" then .[] else . end')"
    # Match versions.
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