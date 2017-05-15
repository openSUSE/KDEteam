#!/bin/bash
if [[ $# -eq 1 ]]; then
    echo "-------------------------------------------------------------------"
    LANG=C date | tr -d '\n'
    echo -e " - fabian@ritter-vogt.de\n"
    echo "- Update to $1"
    echo ""
    exit 0
fi

if [[ $# -ne 5 ]]; then
    echo "Usage is different"
    exit 1
fi

commit_from=$1
commit_to=$2
version_from=$3
version_to=$4
type=$5

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

echo "-------------------------------------------------------------------"
LANG=C date | tr -d '\n'
echo -e " - fabian@ritter-vogt.de\n"
echo "- Update to $version_to"
echo "  * New $type release"
echo "  * For more details please see:"
echo "  * https://www.kde.org/announcements/plasma-$4.php"
commits=$(git log --pretty=format:%H --no-merges $commit_from...$commit_to)

if [ "$(echo -- "$commits" | wc -l)" -gt 100 ]; then
    echo "- Too many changes to list here"
else
    for i in $commits; do
        changes="${changes}$(entryForCommit "$i")"
    done

    if [ "$(echo -e -- "$changes" | wc -l)" -gt 30 ]; then
        echo "- Too many changes to list here"
    else
        echo "- Changes since $version_from:"
        if [ -z "$changes" ]; then
            changes="  * None\n"
        fi

        echo -ne "${changes}"
    fi
fi
echo ""
