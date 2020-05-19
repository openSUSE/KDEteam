#!/bin/bash
if [[ $# -eq 1 ]]; then
    echo "-------------------------------------------------------------------"
    LANG=C TZ=UTC date | tr -d '\n'
    echo -e " - Fabian Vogt <fabian@ritter-vogt.de>\n"
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
        set -f
        # Remove first ','
        for i in ${bugs#,}; do
            echo -n "${i}"
        done
        set +f
        echo -n ")"
    fi

    echo "\n"
}

echo "-------------------------------------------------------------------"
LANG=C TZ=UTC date | tr -d '\n'
echo -e " - Fabian Vogt <fabian@ritter-vogt.de>\n"
echo "- Update to $version_to"
echo "  * New $type release"
echo "  * For more details please see:"
echo "  * https://www.kde.org/announcements/plasma-$4.php"
commits=($(git log --pretty=format:%H --no-merges $commit_from...$commit_to))

if [ "${#commits}" -gt 100 ]; then
    echo "- Too many changes to list here"
else
    reverts=()
    for revert in ${commits[@]}; do
        descr="$(git show -s --pretty=%B "${revert}")"
        if [[ $descr =~ This\ reverts\ commit\ ([0-9a-f]*)\. ]]; then
            reverted="${BASH_REMATCH[1]}"
            reverts+=("${reverted}")
            # Reverted commit in the list?
            if [[ " ${commits[@]} " =~ " ${reverted} " ]]; then
                # Ignore the revert and the reverted commit
                commits=("${commits[@]/$revert}")
                commits=("${commits[@]/$reverted}")
            fi
        fi
    done

    for i in ${commits[@]}; do
        changes="${changes}$(entryForCommit "$i")"
    done

    if [ "$(echo -e -- "$changes" | wc -l)" -gt 30 ]; then
        echo "- Too many changes to list here"
    elif [ -z "$changes" ]; then
        echo "- No code changes since $version_from"
    else
        echo "- Changes since $version_from:"
        echo -ne "${changes}" | uniq
    fi
fi
echo ""
