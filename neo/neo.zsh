#!/bin/zsh

# Update script for managing the KDE releases
#
# First edit the 'common' file.
#
# Before running this utility, you need to update your local osc checkout.
# downloading the released files from the KDE servers isn't automated either.
#
# To synchronize spec files between KDE:Frameworks5 and KDE:Unstable:Frameworks,
# an updated checkout of the KDE:Unstable:Frameworks repository is also needed
#
# The script will:
# - Determine in which folder a tarball shall be moved and remove the need to
#   maintain a list of released applications and special handling rules
# - Move files in the right folders
# - Find the versions automatically and update the spec files accordingly
#
# After that:
# - The local git checkouts will be sync'ed
# - The changelog entry will be created
# - The script takes care of 'silent' commits, removes the reverted ones and
#   avoids duplicate entries in the changelog.
#
# Once the command file is generated, it can be reviewed before being executed
#
# The script shall handle applications, frameworks and plasma releases
#
# TODO Find a name for this script
#
# Usage:
# neo <release_name>
# where release_name is either applications, frameworks or plasma
# 

set -e
set -o pipefail

SCRIPT_DIR=$(dirname "$0")

# Settings
source ${SCRIPT_DIR}/common
# Packages to ignore
source ${SCRIPT_DIR}/ignore_list

zmodload zsh/regex

##### Helper functions #####

# Print an error and exits if anything goes wrong
throw_error() {
  print "ERROR: ${*}" && exit
}

# Print something
debug() {
  print "INFO: ${*}"
}

# Strip the path from a file name (e.g: akonadi-19.07.90.tar.xz)
relative_filename() {
  local _rel_path=${*##*/}
  echo ${_rel_path}
}

# Only return the application name based on the tarball path (e.g: akonadi)
application_name() {
  local _filename=${${*##*/}%-*}
  echo ${_filename}
}

# Return the package name (e.g: akonadi-server)
package_name() {
  local _packagename=${${*%/*}##*/}
  echo ${_packagename}
}

# Return the package path without (e.g /home/johndoe/openSUSE/KDE:Applications/akonadi-server)
package_path() {
  local _packagepath=${*%/*}
  echo ${_packagepath}
}


# To allow reviewing the commands to run, this script creates a shell list
write_command() {
  echo $* >> ${UPDATE_SCRIPT_DIR}/update_packages
}
# Create the file
echo "#!/bin/zsh" > ${UPDATE_SCRIPT_DIR}/update_packages
write_command "#"

############################

# Local variables
local -a packages_to_update
local -a new_packages

release_name=($*)

check_release_name() {
  # Check how many parameters were passed
  [[ ${#release_name[@]} -ne 1 ]] && throw_error "Incorrect number of parameters"

  # Check if the parameter matches RELEASE_NAME
  [[ -n "${RELEASE_NAME[(r)${release_name[1]}]}" ]] || throw_error "Wrong parameter. Must be one of: ${RELEASE_NAME}"

  # Check if the directories exist
  foreach _local_dir (TARBALLS_DIR OBS_DIR GIT_DIR) {
    [[ -d ${(P)_local_dir} ]] || throw_error "${_local_dir} doesn't exist. edit the common file"
  }
}

# List all the newly released files
list_new_tarballs() {
  new_tarballs=(${TARBALLS_DIR}/*.${EXT})
}

# Find the new version.
find_new_version() {
 new_version=${${new_tarballs[1]%.${EXT}}##*-}
}

# List the current packages files
list_packaged_tarballs() {
  case ${release_name} in
    applications) repository_name="KDE:Applications" ;;
    frameworks)   repository_name="KDE:Frameworks5"  ;;
    plasma)       repository_name="KDE:Frameworks5"  ;;
  esac
  packaged_tarballs=(${OBS_DIR}/${repository_name}/*/*.${EXT})

  # Remove the packages from the ignore list
  foreach pkg (${ignore_list}) {
    packaged_tarballs[(r)${OBS_DIR}/${repository_name}/${pkg}/*]=()
  }

  # Stop if the KDE:Unstable:Frameworks repository checkout cannot be found
  if [[ ${release_name} == "frameworks" ]]; then
    [[ -d "${OBS_DIR}/KDE:Unstable:Frameworks" ]] || throw_error "KDE:Unstable:Frameworks is also needed before updating the frameworks packages"
  fi
}

# Based on the tarball name, find which packages shall be updated
find_packages_to_update() {
  local _new_tarballs=($(application_name ${new_tarballs}))

  # We create a temporary unsorted array to store the list of packages to update
  # This way we'll be sure the array position matches
  local _sorted_packaged_tarballs=()

  foreach _package (${_new_tarballs}) {
    _pattern="*${_package}-[0-9]*"
    if (( ${packaged_tarballs[(I)${_pattern}]} )); then
      # Match found
      _sorted_packaged_tarballs+=${packaged_tarballs[(r)${_pattern}]}

      # Write the osc command to branch these packages
      write_command osc branch ${repository_name} $(package_name ${packaged_tarballs[(r)${_pattern}]}) home:${OBS_USERNAME}:${release_name}-${new_version}
    else
      # New packages
      new_packages+=${_package}

      # Remove them from the list of tarballs to proceed
      new_tarballs[(r)${_pattern}]=()
    fi
  }
  debug New packages in this release: ${new_packages}

  # The list is now trimmed, only keep the useful packages
  packaged_tarballs=(${_sorted_packaged_tarballs})
}

# Now set the old version
find_old_version() {
 old_version=${${packaged_tarballs[1]%.${EXT}}##*-}
}

# Write commands to download the branched packages
obs_checkout_branch() {
  branched_checkout_dir="home:${OBS_USERNAME}:${release_name}-${new_version}"
  write_command pushd ${OBS_DIR}
  write_command osc checkout ${branched_checkout_dir}
}

# Commands to replace the old files with the new ones
replace_files() {
  write_command mkdir -p ${TARBALLS_DIR}/done
  # The item positions in both the packaged_tarballs and new_tarballs arrays
  # shall match at this point
  # copy the new file and signature and move them to the 'done' subdir
  
  for (( i = 1; i <= $#new_tarballs; i++ )); do
    write_command ""
    write_command cp ${new_tarballs[$i]} ${OBS_DIR}/${branched_checkout_dir}/$(package_name ${packaged_tarballs[$i]})
    write_command mv ${new_tarballs[$i]} $(package_path ${new_tarballs[$i]})/done
    
    write_command "    if [[ -f ${new_tarballs[$i]}.sig ]]; then
      cp -f ${new_tarballs[$i]}.sig ${OBS_DIR}/${branched_checkout_dir}/$(package_name ${packaged_tarballs[$i]})
      mv ${new_tarballs[$i]}.sig $(package_path ${new_tarballs[$i]})/done
    fi"
    # Remove the old files
    write_command rm -f ${OBS_DIR}/${branched_checkout_dir}/$(package_name ${packaged_tarballs[$i]})/$(relative_filename ${packaged_tarballs[$i]})
    write_command "[[ -f ${packaged_tarballs[$i]}.sig ]] && rm -f ${OBS_DIR}/${branched_checkout_dir}/$(package_name ${packaged_tarballs[$i]})/$(relative_filename ${packaged_tarballs[$i]}).sig"
  done
  write_command ""
}

# Create the temp folder that will host the changelog files and start generating
# the changelog entry.

prepare_changelog() {
  mkdir -p ${TARBALLS_DIR}/changelogs
  # xx.yy.0 -> feature
  # xx.yy.[1-9] -> bugfix
  # xx.yy.[80-89] -> feature (beta)
  # xx.yy.[90-99] -> feature (rc)
  major_version=${new_version%%.*}
  minor_version=${${new_version#*.}%.*}
  patch_version=${new_version##*.} 

  if [[ ${patch_version} -eq 0 ]] || [[ ${patch_version} -ge 80 ]] && release_type=feature || release_type=bugfix

  # The announce URL is different for applications, frameworks and plasma
  if [[ ${release_name} == frameworks ]]; then
    changelog_url=${ANNOUNCE_URL}/kde-frameworks-${new_version}.php
  elif [[ ${release_name} == plasma ]]; then
    changelog_url=https://www.kde.org/announcements/plasma-${new_version}.php
  else
    if [[ ${patch_version} -lt 80 ]]; then
      changelog_url=${ANNOUNCE_URL}/announce-applications-${new_version}.php
    else
      # The applications URL is different for beta and RC
      # 19.07.xx == 19.08-{beta,rc}
      if [[ $patch_version -lt 90 ]]; then
        changelog_url=${ANNOUNCE_URL}/announce-applications-${major_version}.0$((${minor_version} + 1))-beta.php
      else
        changelog_url=${ANNOUNCE_URL}/announce-applications-${major_version}.0$((${minor_version} + 1))-rc.php
      fi
    fi
  fi
  
  changelog_intro="Update to ${new_version}
  * New ${release_type} release
  * For more details please see:
  * ${changelog_url}\n"
}

# Update the GIT repository (or checkout the missing ones), fetch changes since
# the last release and write the changelog entries
fetch_changes() {
  pushd ${GIT_DIR}

  # Init
  local -a changelog_body
  local -a reverted_commits
  local -aU changelog_entries

  foreach git_repo ($(application_name ${new_tarballs})) {

    [[ -d ${git_repo} ]] || git clone git://anongit.kde.org/${git_repo}
    
    pushd ${git_repo}

    # 
    git fetch origin &>/dev/null

    # Fetch the existing tags
    tags=($(git tag))

    ## Special cases
    # If the tag wasn't pushed yet, use the branch to get changelog entries
    if [[ ! -n ${tags[(r)v${new_version}]} ]]; then
      if [[ "${release_name}" == applications ]]; then
        new_tag="origin/Applications/${major_version}.${minor_version}"
      elif [[ "${release_name}" == plasma ]]; then
        new_tag="origin/Plasma/${major_version}.${minor_version}"
      else
        # Frameworks pre-release tags are called v${new_version}-rcX
        # TODO handle rc2, rc3...
        new_tag="v${new_version}-rc1"
      fi
    else
      new_tag="v${new_version}"
    fi

    old_tag="v${old_version}"

    commits=($(git log --pretty=format:%H --no-merges ${old_tag}...${new_tag}))

    foreach commit (${commits}) {
      
      if [[ -n "${reverted_commits[(Ie)${commit}]}" ]]; then
        commit_log="$(git show -s ${commit})"

        # If the commit is a revert, add the reverted one to the list and jump to
        # the next one
        if [[ ${commit_log} =~ "This reverts commit" ]]; then
          reverted_commits+=${${commit_log##*This reverts commit }%%.*}
        else
          # Ignore commits if the commit message contains GIT_SILENT or SVN_SILENT
          if [[ ! ${commit_log} =~ _SILENT ]]; then
            commit_summary="$(git show -s --pretty=format:%s ${commit})"

            # Now look for the 'BUG' keyword (and skip CCBUG)
            if [[ "${commit_log}" -regex-match '.*^\s*BUG' ]]; then

              # 1/ Remove anything before 'BUG*:'
              # 2/ Remove every line after the one with bug numbers
              # 3/ Replace commas with spaces
              # echo is needed to strip unneeded spaces
              commit_bugs=($(echo ${${${commit_log#*BUG*:}%%$'\n'*}/,/ }))
              
              # Then wrap the bug numbers with '(kde#)'
              obs_bug_entry=" (kde#${commit_bugs[1]}"
              for (( i = 2; i <= $#commit_bugs; i++ )); do
                obs_bug_entry+=", kde#${commit_bugs[$i]}"
              done
              obs_bug_entry+=")"
            fi
            changelog_entries+="\n  * ${commit_summary}${obs_bug_entry}"

            unset obs_bug_entry
          fi
        fi
      fi
    }

    if [[ ${changelog_entries} == "" ]]; then
      changelog_body="- No code change since ${old_version}"
    else
      changelog_body="- Changes since ${old_version}:"
      changelog_body+="${changelog_entries}"
    fi
    # The changelog is complete, save it
    echo ${changelog_intro}${changelog_body} > ${TARBALLS_DIR}/changelogs/${git_repo}.changes
    popd

    # Reset variables
    unset git_stash_branch
    unset commits
    unset commit
    unset commit_log
    unset commit_summary
    unset commit_bugs
    unset obs_bug_entry
    changelog_body=()
    changelog_entries=()
    reverted_commits=()    
  }
  popd
}

# Update the version and URL in the spec file
update_spec_file() {
  for (( i = 1; i <= $#packaged_tarballs; i++ )); do
    write_command pushd ${OBS_DIR}/${branched_checkout_dir}/$(package_name ${packaged_tarballs[$i]})
    write_command osc vc -F ${TARBALLS_DIR}/changelogs/$(application_name ${new_tarballs[$i]}).changes
    
    # For frameworks release, first copy the .spec file from the KDE:Unstable:Frameworks package
    if [[ ${release_name} == "frameworks" ]]; then
      write_command cp -f ${OBS_DIR}/KDE:Unstable:Frameworks/$(package_name ${packaged_tarballs[$i]})/*.spec .
    fi
    
    write_command "perl -pi -e 's#${old_version}#${new_version}#g' $(package_name ${packaged_tarballs[$i]}).spec"
    
    # Check if the 'Source' URL shall be updated in the spec file
    [[ $patch_version -ge 80 ]] && new_download_url_dir=unstable || new_download_url_dir=stable
    old_patch_version=${old_version##*.}
    [[ $old_patch_version -ge 80 ]] && old_download_url_dir=unstable || old_download_url_dir=stable
    
    if [[ "${old_download_url_dir}" != "${new_download_url_dir}" ]]; then
      write_command "perl -pi -e 's#download.kde.org/${old_download_url_dir}#download.kde.org/${new_download_url_dir}#g' $(package_name ${packaged_tarballs[$i]}).spec"
    fi
  done
}

# Run each function
check_release_name
list_new_tarballs
find_new_version
list_packaged_tarballs
find_packages_to_update
find_old_version
obs_checkout_branch
replace_files
prepare_changelog
fetch_changes
update_spec_file

# Make the command script executable
chmod +x ${UPDATE_SCRIPT_DIR}/update_packages

# Report
debug The update script is ready.
debug Check the changelog files in ${TARBALLS_DIR}/changelogs. When ready, run the ${UPDATE_SCRIPT_DIR}/update_packages script
