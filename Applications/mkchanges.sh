#!/bin/bash

source $(realpath "$(dirname "$0")")/common

if [[ $# -eq 1 ]]; then
    echo "-------------------------------------------------------------------"
    LANG=C date | tr -d '\n'
    echo -e " - ${committer}\n"
    echo "- Update to $1"
    echo ""
    exit 0
fi

if [[ $# -ne 6 ]]; then
    echo "Usage is different"
    exit 1
fi

commit_from=$1
commit_to=$2
version_from=$3
version_to=$4
type=$5
kind=$6

function entryForCommit {
    commit="$1"
    subject="$(git show -s --pretty=format:%s "$commit")"

    # Ignore GIT_SILENT/SVN_SILENT
    if [[ "${subject/_SILENT}" != "${subject}" ]]; then
        return
    fi

    echo -n "  * ${subject}"

    # Get bugrefs
    bugs="$(git show -s "$commit" | grep -E '^\s*BUG:' | cut --delimiter=: --fields=2 | sed 's/^/,kde#/')"

    if [[ -n "${bugs}" ]]; then
        echo -n " ("
        # Remove first ','
        for i in ${bugs#,}; do
            echo -n "${i}"
        done
        echo -n ")"
    fi

    echo "\n"
}

full_url=""

case $kind in
    "applications")
        full_url="$base_url/$applications_url"
        ;;
    "frameworks")
        full_url="$base_url/$kf5_url"
        ;;
    "plasma")
        full_url="$base_url/$plasma_url"
        ;;
esac

echo "-------------------------------------------------------------------"
LANG=C date | tr -d '\n'
echo -e " - ${committer}\n"
echo "- Update to $version_to"
echo "  * New $type release"
echo "  * For more details please see:"
echo "  * $full_url"
commits=$(git log --pretty=format:%H --no-merges $commit_from...$commit_to)
if [ "$(echo -- "$commits" | wc -l)" -gt 30 ]; then
    changes="- Too many changes to list here"
else
    for i in $commits; do
        changes="${changes}$(entryForCommit "$i")"
    done

    echo "- Changes since $version_from:"
    if [ -z "$changes" ]; then
        changes="  * None"
    fi
fi
echo -e "$changes"
echo ""
