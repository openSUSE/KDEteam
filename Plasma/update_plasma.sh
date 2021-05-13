#!/bin/bash
# Run in (branch of) KDE:Frameworks5
# Attention: Reads and overwrites /tmp/change{,s}

# Version number
version_from="5.16.5"
version_to="5.16.90"
# Git refs
commit_from="v5.16.5"
commit_to="origin/Plasma/5.17"
# Type of update, either "bugfix" or "feature"
type="feature"
# Location of plasma repo checkouts (need to be fresh)
repo_location="/home/fabian/kderepos"
# Location of downloaded tars. Will be used if available
tar_location="/home/fabian/plasmatars"
# If empty, URL will be stripped from source
#tar_url="https://download.kde.org/unstable/plasma/%{version}/"
tar_url=""

script_dir=$(realpath "$(dirname "$0")")

pkgs="$@"
if [ "$pkgs" = "" ]; then
    pkgs="*"
fi

for i in $pkgs; do
    echo "Updating $i:"
    cd $i
    if [[ "$i" == "plasma5-openSUSE" ]]; then
        spec_version="${version_from}"
        sed -i "s/${version_from}/${version_to}/g" *.spec
    else
        spec_version="$(rpmspec -q --srpm --qf %{version} $i.spec)"
        sed -i "s/^Version:        ${spec_version//\./\\.}/Version:        $version_to/g" *.spec
    fi
    echo -e "\tSpecfile updated"
    reponame=$(rpmspec -q --srpm --qf '[%{SOURCE}\n]' $i.spec | grep '.tar.xz$' | sed "s/-5.*//")
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

    rm -f *.tar.xz *.tar.xz.sig

    if rpmspec -q --srpm --qf '[%{SOURCE}\n]' $i.spec | grep -q '.sig$'; then
        needs_signature=1
    else
        needs_signature=0
    fi

    # Adjust Source URL
    sed -i 's#Source:.*$#Source:         '${tar_url}${reponame}'-%{version}.tar.xz#' *.spec
    sed -i 's#Source0:.*$#Source0:        '${tar_url}${reponame}'-%{version}.tar.xz#' *.spec
    [ $needs_signature = 1 ] && sed -i 's#Source1:.*$#Source1:        '${tar_url}${reponame}'-%{version}.tar.xz.sig#' *.spec

    tar_path="${tar_location}/${reponame}-${version_to}.tar.xz"
    if [ -e "${tar_path}" ]; then
        cp ${tar_path} .
        [ $needs_signature ] && cp ${tar_path}.sig .
        echo -e "\tArchive copied"
    else
        echo -e "\tTrying to download"
        osc service localrun download_files >/dev/null 2>&1
        if [ -f *.tar.xz ]; then
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
