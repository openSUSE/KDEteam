#!/bin/bash
# Run in (branch of) KDE:Frameworks6
# Attention: Reads and overwrites /tmp/change{,s}

set -euo pipefail

# Version number
version_from="6.3.4"
version_to="6.3.5"
# Git refs
commit_from="v${version_from}"
commit_to="v${version_to}"
# Type of update, either "bugfix" or "feature"
type="bugfix"
# Location of plasma repo checkouts (need to be fresh)
repo_location="/home/fabian/kderepos"
# Location of downloaded tars. Will be used if available
tar_location="/home/fabian/plasmatars"
# If empty, URL will be stripped from source
tar_url="https://download.kde.org/stable/plasma/%{version}/"

script_dir=$(realpath "$(dirname "$0")")

pkgs="$@"
if [ "$pkgs" = "" ]; then
    pkgs="*"
fi

for i in $pkgs; do
    echo "Updating $i:"
    cd $i
    if grep -q "\- Update to ${version_to}:" *.changes; then
        echo -e "\tAlready done"
        cd ..
        continue
    fi
    if [[ "$i" == "plasma6-openSUSE" ]]; then
        spec_version="${version_from}"
        sed -i 's/plasma_version [56].*$/plasma_version '"${version_to}/g" *.spec
        { "${script_dir}/mkchanges.sh" "$version_to"; cat *.changes; } | sponge *.changes
        echo -e "\tSpecfile updated"
        cd ..
        echo -e "\tDone"
        continue
    elif [[ "$i" == "kirigami-addons6" ]]; then
        echo -e "\tNot handled!"
        cd ..
        continue
    else
        spec_version="$(rpmspec -q --srpm --qf %{version} $i.spec)"
        sed -i "s/^Version:        ${spec_version//\./\\.}/Version:        $version_to/g" *.spec
    fi
    if [ -e "_service" ]; then
        rm _service
        echo -e "\t_service deleted"
    fi
    echo -e "\tSpecfile updated"
    reponame=$(rpmspec -q --srpm --qf '[%{SOURCE}\n]' $i.spec | grep '.tar.xz$' | sed -E 's/-[^-]+$//')
    if [ -e "${script_dir}/plasma-${version_to}-release-data" ]; then
        commit_to="$(awk -F\; "\$1 == \"${reponame}\" { print \$3 }" "${script_dir}/plasma-${version_to}-release-data")"
    fi

    rm -f *.tar.xz *.tar.xz.sig

    # Adjust Source URL
    sed -i 's#Source:.*$#Source:         '${tar_url}%{rname}'-%{version}.tar.xz#' *.spec
    sed -i 's#Source0:.*$#Source0:        '${tar_url}%{rname}'-%{version}.tar.xz#' *.spec
    sed -i 's#Source1:.*.sig$#Source1:        '${tar_url}%{rname}'-%{version}.tar.xz.sig#' *.spec

    tar_path="${tar_location}/${reponame}-${version_to}.tar.xz"
    if [ -e "${tar_path}" ]; then
        cp ${tar_path} .
        cp ${tar_path}.sig .
        echo -e "\tArchive copied"
    else
        echo -e "\tTrying to download"
        osc service runall download_files >/dev/null 2>&1 || echo -e "\t\tFailed?"
        if [ -f *.tar.xz ]; then
            echo -e "\t\tDone"
        else
            echo -e "\t\tFailed!"
        fi
    fi

    if ! [ -e "plasma.keyring" ]; then
        cp "${script_dir}/plasma.keyring" .
        echo -e "\tCopied keyring"
    fi

    if [ -n "${commit_from}" ] && [ -d "$repo_location/$reponame" ]; then
        (cd "${repo_location}/${reponame}"; git fetch origin --tags; "${script_dir}/mkchanges.sh" "$commit_from" "$commit_to" "$version_from" "$version_to" "$type") > /tmp/change
    else
        echo -e "\tNo checkout for $reponame"
        "${script_dir}/mkchanges.sh" "$version_to" > /tmp/change
    fi

    for c in *.changes; do
        cat /tmp/change $c > /tmp/changes
        mv /tmp/changes $c
    done
    cd ..
    echo -e "\tDone"
done

echo "Done"
