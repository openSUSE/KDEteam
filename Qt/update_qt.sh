#!/bin/bash
# Run in (branch of) KDE:Qt:5.x
# Attention: Reads and overwrites /tmp/change{,s}

# Version number
version_from="5.11.0-alpha"
version_to="5.11.0-beta1"
minor_from="5.11"
minor_to="5.11"
# "development_releases" or "official_releases"
release_dir="development_releases"
# Type of update, either "bugfix" or "feature"
type="feature"

# Derived stuff
rpm_version="${version_to/-/\~}"
real_version="${version_to}"
so_version="${version_to%%-*}"

script_dir=$(realpath "$(dirname "$0")")

pkgs="$@"
if [ "$pkgs" = "" ]; then
    pkgs="$(cat "${script_dir}/pkglist${minor_from}")"
fi

for i in $pkgs; do
    echo "Updating $i:"
    cd $i

    sed -i "s/^Version:.*$/Version:        ${rpm_version}/g" *.spec
    sed -i "s/^%define real_version .*$/%define real_version ${real_version}/g" *.spec
    sed -i "s/^%define so_version .*$/%define so_version ${so_version}/g" *.spec
    sed -i "s/^%define tar_version \(.*-src\)-.*$/%define tar_version \\1-${real_version}/g" *.spec
    sed -i "s#/${minor_from}/#/${minor_to}/#g" *.spec
    sed -i "s#/[^/]*_releases/#/${release_dir}/#g" *.spec

    echo -e "\tSpecfile updated"

    reponame=$(echo *.tar.xz)
    reponame=${reponame%%-*}

    rm *.tar.xz

    echo -e "\tTrying to download"
    osc service localrun download_files >/dev/null 2>&1
    if [ -e *.tar.xz ]; then
        echo -e "\t\tDone"
    else
        echo -e "\t\tFailed"
    fi

    "${script_dir}/mkchanges.sh" "${reponame}" "${version_from}" "${version_to}" "${type}" > /tmp/change
    for c in *.changes; do
        cat /tmp/change $c > /tmp/changes
        mv /tmp/changes $c
    done
    cd ..
    echo -e "\tDone"
done

echo "Done"
