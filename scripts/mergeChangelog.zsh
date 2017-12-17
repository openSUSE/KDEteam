mergeChangelog() {
zmodload zsh/regex
    # Either paste this function into ~/.zshrc or run source mergeChangelog.zsh
    # Usage mergeChangelog <changelog1> <changelog2>
    # Result will be merged in both files
    local mergedChangelog indexes sortedindexes sortedChangelog
    typeset -AU mergedChangelog
    typeset -U indexes sortedindexes

    DELIM="-------------------------------------------------------------------"

    changelogs=("${1}" "${2}")

    regex='^.*[0-9]{4}\s+-.*@.*$'

    foreach changelog (${changelogs}) {
        foreach changelog_entry ("${(ps:$DELIM:)$(<${changelog})}") {
            # Each changelog entry is split, we want to look for the date
            foreach line ("${(@f)${changelog_entry}}") {
              if [[ "${line}" -regex-match "${regex}" ]]; then
                  # We have a timestamp
                  timestamp=$(date +%s -d "${line[(ws: - :)1]}")
                  mergedChangelog[${timestamp}]=${changelog_entry}
                  indexes+=(${timestamp})
              fi
            }
        }
    }
    # The array is created, let's sort the entries
    sortedindexes=(${(@On)indexes[*]})
    foreach index (${sortedindexes}) {
        sortedChangelog+="${DELIM}"
        sortedChangelog+="$mergedChangelog[$index]"
    }
    foreach changelog (${changelogs}) {
cat > ${changelog} << EOF
${sortedChangelog}
EOF
    }

zmodload -u zsh/regex
}
