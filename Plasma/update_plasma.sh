#!/bin/bash
# Run in (branch of) KDE:Frameworks5
# Attention: Reads and overwrites /tmp/change{,s}

# Version number
version_from="5.9.2"
version_to="5.9.3"
# Git refs
commit_from="v5.9.2"
commit_to="v5.9.3"
# Type of update, either "bugfix" or "feature"
type="bugfix"
# Location of plasma repo checkouts (need to be fresh)
repo_location="/home/fabian/plasma"
# Location of downloaded tars. Will be used if available
tar_location="/home/fabian/plasma/tars"
# If empty, URL will be stripped from source
tar_url="http://download.kde.org/stable/plasma/%{version}/"

script_dir=$(realpath "$(dirname "$0")")

for i in *; do
    echo "Updating $i:"
    cd $i
    sed -i "s/$version_from/$version_to/g" *.spec
    echo -e "\tSpecfile updated"
    reponame=$(echo *.tar.xz | sed "s/-5.*//")
    if [ ! -d "$repo_location/$reponame" ]; then
        echo -e "\tNo checkout for $i"
        "${script_dir}/mkchanges.sh" "$version_to" > /tmp/change
        for c in *.changes; do
            cat /tmp/change $c > /tmp/changes
            mv /tmp/changes $c
        done
        cd ..
        continue
    fi

    rm *.tar.xz

    # Adjust Source URL
    sed -i 's#Source:.*$#Source:         '${tar_url}${reponame}'-%{version}.tar.xz#' *.spec

    tar_path="${tar_location}/${reponame}-${version_to}.tar.xz"
    if [ -e "${tar_path}" ]; then
        cp ${tar_path} .
        echo -e "\tArchive copied"
    else
        echo -e "\tTrying to download"
        osc service localrun download_files >/dev/null 2>&1
        if [[ -n "*.tar.xz" ]]; then
            echo -e "\t\tDone"
        else
            echo -e "\t\tFailed"
        fi
    fi

    (cd "${repo_location}/${reponame}"; "${script_dir}/mkchanges.sh" "$commit_from" "$commit_to" "$version_from" "$version_to" "$type") > /tmp/change
    for c in *.changes; do
        cat /tmp/change $c > /tmp/changes
        mv /tmp/changes $c
    done
    cd ..
    echo -e "\tDone"
done

echo "Done"
