# Helper function to merge changelog entries between two repositories
# The changelog may be synced in one or both repositories.
#
# NEWS:
# 2018-08-27:
# * mergeChangelog now accepts either changelog files or repositories name.
# * Added a '--oneway' option. Only the second changelog/repository will be modified.
# * Improve doc.
# * Print issues found when parsing the changelog files.

_mc_help() {
    _mc_help="Usage: mergeChangelog source1 source2 [--oneway]

    Merge the changes between either two changelog files or repositories.
    The paths may be relative or absolute.

Commands:
    --oneway    Only 'changelog2' or packages in 'repository2' will be modified.

Examples:
    mergeChangelog KDE:Extra/krita/krita.changes KDE:Unstable:Extra/krita/krita.changes
    Will fill both changelog files with the missing entries from the other package

    mergeChangelog KDE:Applications KDE:Unstable:Applications --oneway
    The command will modify changelog entries for every packages in KDE:unstable:Applications
    that also exist in KDE:Applications

"
    print "${_mc_help}"
}

_mc_print_error() {
    # Print the error and the help if something is wrong
    if [[ ${_mc_error} != "" ]]; then
        print "${_mc_error}\n"
        _mc_help && return 1
    fi
}

_mc_parse_args() {
    _mc_error=""
    _mc_onewayArg="--oneway"
    _mc_args=($*)
    # Don't fail if --oneway is not the last argument
    if [[ -n ${(M)_mc_args:#${_mc_onewayArg}} ]]; then
        _mc_oneway=1
        _mc_args=(${(@)_mc_args:#${_mc_onewayArg}})
    fi
    [[ ${#_mc_args[@]} -ne 2 ]] && _mc_error="Wrong arguments count"

    _mc_print_error || return

    # Check if the arguments are files or directories
    # Also Print an error if they were mixed
    _mc_arg1=${_mc_args[1]}
    _mc_arg2=${_mc_args[2]}
    foreach n (${_mc_arg1} ${_mc_arg2}) {
        [[ ! -f ${n} && ! -d ${n} ]] && _mc_error+="File or directory doesn't exist: ${n}\n"
    }

    _mc_print_error || return

    if [[ -f ${_mc_arg1} && -d ${_mc_arg2} ]] || [[ -d ${_mc_arg1} && -f ${_mc_arg1} ]]; then
        _mc_error="Arguments mismatch. Don't mix directories and files"
    fi

    _mc_print_error || return
}

mergeChangelog() {
    _mc_parse_args ${*} || return

    local changesFileList1 changesFileList2 repo1 repo2

    if [[ -f ${_mc_arg1} ]]; then
      # Absolute path to the repo
      repo1="${_mc_arg1:a:h:h}"
      repo2="${_mc_arg2:a:h:h}"

      # mypackage/mypackage.changes
      _changesFileList1=(${_mc_arg1:a})
      _changesFileList2=(${_mc_arg2:a})
    else
      repo1="${_mc_arg1:a}"
      repo2="${_mc_arg2:a}"
      _changesFileList1=(${repo1}/*/*.changes)
      _changesFileList2=(${repo2}/*/*.changes)
    fi

    changesFilesList1=(${_changesFileList1#${repo1}/})
    changesFilesList2=(${_changesFileList2#${repo2}/})

    DELIM="-------------------------------------------------------------------"

    foreach changeLogFile (${changesFilesList1}) {
        # Don't do anything if the changelog file doesn't exist in both
        # repositories
        if [[ -n ${(M)changesFilesList2:#${changeLogFile}} ]]; then
            local -a changelogs indexes mergedChangelog
            typeset -AU mergedChangelog
            typeset -U indexes
            changelogs=("${repo1}/${changeLogFile}" "${repo2}/${changeLogFile}")

            regex='^.*[0-9]{4}\s+-.*'

            foreach changelog (${changelogs}) {
                # We need an extra step to keep the empty newline in the first
                # changelog entry
                changelog_content="$(<${changelog})"
                changelog_content+=$'\n\n'
                foreach changelog_entry (${(ps:$DELIM:)changelog_content}) {
                    local -a failures
                    # Each changelog entry is split, we're validating the date
                    header=${${(f)${changelog_entry}}[1]}
                    if [[ "${header}" =~ "${regex}" ]]; then
                        # We have a date, check whether it's valid
                        entry_date=${header[(ws: - :)1]}
                        timestamp=$(date +%s -d "${entry_date}" 2&>/dev/null)
                        if [[ $? -eq 1 ]]; then
                            failures+="${entry_date}"
                            unset entry_date
                        else
                            mergedChangelog[${timestamp}]=${changelog_entry}
                            indexes+=(${timestamp})
                        fi
                    else
                        failures+="${header}"
                    fi
                    unset header
                }
                unset changelog_content

            if [[ ${failures} != "" ]]; then
                print "Invalid entries were found in ${changelog}:"
                foreach failure (${failures}) {
                    printf "-> ${failure}\n"
                }
                unset failures
                doNotModifyFiles=1
            fi
            }
            unset changelogs
            if [[ ${doNotModifyFiles} -eq 1 ]]; then
                print "Fix the changelog entries and run mergeChangelog again for these packages.\n"
                unset doNotModifyFiles
            else
                local -a sortedindexes sortedChangelog
                typeset -U sortedindexes
                # The array is created, let's sort the entries
                sortedindexes=(${(@On)indexes[*]})
                sortedChangelog=""
                foreach index (${sortedindexes}) {
                    sortedChangelog+="${DELIM}"
                    sortedChangelog+="$mergedChangelog[$index]"
                }
                # And now we remove the extra newline at the bottom
                sortedChangelog=${sortedChangelog%$'\n'}

                cat > ${repo2}/${changeLogFile} << EOF
${sortedChangelog}
EOF
                if [[ ${_mc_oneway} -ne 1 ]]; then
                    cat > ${repo1}/${changeLogFile} << EOF
${sortedChangelog}
EOF
                fi
            fi
       fi
    # Clear the arrays
    unset mergedChangelog indexes sortedindexes sortedChangelog
    }
}
