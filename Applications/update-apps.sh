#!/usr/bin/zsh
set -e
setopt nounset
unsetopt nomatch

#Set variables used by this script

. $(realpath "$(dirname "$0")")/common

OLDPATCH=/tmp/patches.old
NEWPATCH=/tmp/patches.new
DIFFPATCH=/tmp/patches.diff

submit_package() {
  # Submit package to OBS
  package=$1
  src_pack=$2

  cd $kde_obs_dir/
  if osc api /source/KDE:Applications/$package >/dev/null 2>&1; then
          osc co $package
          cd $package
  else
	  osc copypac KDE:Unstable:Applications $package KDE:Applications
	  osc co $package
          cd $package
	  rm _service
  fi

  # Determine current version
  kde_cur_version=`cat ${package}.spec | grep 'Version:' | awk {'print $2'}`

  echo "Updating ${package} from $kde_cur_version to $kde_new_version"

  # Determine existing patches
  cat ${package}.spec | grep '^Patch' | awk {'print $2'} > ${OLDPATCH}

  # Get the new spec-file for KDE:Unstable:Applications
  osc co KDE:Unstable:Applications ${package} ${package}.spec
  kde_sem_version=`cat ${package}.spec | grep 'Version:' | awk {'print $2'}`

  # Determine new patches
  cat ${package}.spec | grep '^Patch' | awk {'print $2'} > ${NEWPATCH}

  echo "Determining patches"
  # Validate for dropped or new patches
  `diff ${OLDPATCH} ${NEWPATCH} > ${DIFFPATCH} ||:`
  echo "Dropped patches"
  dropped=`cat ${DIFFPATCH} | grep '^<' | awk {'print $2'}`
  echo "Added patches"
  added=`cat ${DIFFPATCH} | grep '^>' | awk {'print $2'}`

  echo "Dropping patches"
  # Drop removed patches
  for i in `echo $dropped`
  do
	  rm $i
  done

  echo "Adding new/updated patches"
  for i in `cat ${NEWPATCH}`
  do
	  osc co KDE:Unstable:Applications ${package} $i
  done


  echo "Removing old tarballs"
  # Remove old tarball and add new one
  OLDTAR="${src_pack}-*.tar.xz"
  echo ${src_pack}
  echo ${OLDTAR}
  for f in `find . -maxdepth 1 -name $OLDTAR -print`; do
	  echo "Remove $f"
	  rm $f
  done

  echo "Prepare changelog"
  # Create a proper changelog for the patches
  NEWLINE=$'\n'
  changes=""
  if [[ -n "$dropped" ]]  then
	  changes="$changes${NEWLINE}- Dropped patches:"
	  for i in `echo $dropped`
	  do
		  changes="${changes}${NEWLINE}   + ${i}"
	  done
  fi
  if [[ -n "$added" ]]; then
	  changes="$changes${NEWLINE}- Added patches:"
	  for i in `echo $added`
	  do
		  changes="${changes}${NEWLINE}   + ${i}"
	  done
  fi

  echo "Update Spec-file"
  # Update the spec file
  case "$package" in
              kde-l10n)
                      cp ${kde_sources}/${src_pack}-*-${kde_new_version}.tar.xz .
                      mv ${kde_sources}/${src_pack}-*-${kde_new_version}.tar.xz ${kde_sources}/done/
		      sed -i "s/$kde_sem_version/$kde_new_version/g" ${package}.spec.in
                      sh ./pre_checkin.sh;
                      osc vc $package.changes -m"${CHANGELOG}$changes";
                      ;;
              *)
                      cp ${kde_sources}/${src_pack}-${kde_new_version}.tar.xz .
                      mv ${kde_sources}/${src_pack}-${kde_new_version}.tar.xz ${kde_sources}/done/
		      sed -i "s/$kde_sem_version/$kde_new_version/g" ${package}.spec
                      osc vc $package.changes -m"${CHANGELOG}$changes";
	       ;;
  esac

  echo "Final commit"
  # Commit the new snapshot
  osc addremove
  osc ci --noservice -m "update to (${kde_new_version})"
  cd $kde_obs_dir/
  rm -rf $package
}

submit_kde4_package() {
  # Submit package to OBS
  package=$1
  src_pack=$2

  cd $kde_obs_dir/
  osc co $package
  cd $package

  # Determine current version
  kde_sem_version=`cat ${package}.spec | grep 'Version:' | awk {'print $2'}`

  echo "Updating ${package} from $kde_sem_version to $kde_new_version"

  echo "Changing tarball"
  # Remove old tarball and add new one
  OLDTAR="${src_pack}-*.tar.xz"
  echo ${src_pack}
  echo ${OLDTAR}
  for f in `find . -maxdepth 1 -name $OLDTAR -print`; do
	  echo "Remove $f"
	  rm $f
  done

  echo "Update Spec-file"
  # Update the spec file
  case "$package" in
              kdelibs4)
                      cp ${kde_sources}/${src_pack}-${kdelibs_new_version}.tar.xz .
                      mv ${kde_sources}/${src_pack}-${kdelibs_new_version}.tar.xz ${kde_sources}/done/
		      sed -i "s/$kde_sem_version/$kdelibs_new_version/g" ${package}.spec
                      osc vc $package.changes -m"${CHANGELIBLOG}" ;
                      sh ./pre_checkin.sh;
                      ;;
              kde-l10n)
                      cp ${kde_sources}/${src_pack}-*-${kde_new_version}.tar.xz .
                      mv ${kde_sources}/${src_pack}-*-${kde_new_version}.tar.xz ${kde_sources}/done/
		      sed -i "s/$kde_sem_version/$kde_new_version/g" ${package}.spec.in
                      osc vc $package.changes -m"${CHANGELOG}";
                      sh ./pre_checkin.sh;
                      ;;
              *)
                      cp ${kde_sources}/${src_pack}-${kde_new_version}.tar.xz .
                      mv ${kde_sources}/${src_pack}-${kde_new_version}.tar.xz ${kde_sources}/done/
		      sed -i "s/$kde_sem_version/$kde_new_version/g" ${package}.spec
                      osc vc $package.changes -m"${CHANGELOG}";
	       ;;
  esac

  echo "Final commit"
  # Commit the new snapshot
  osc addremove
  osc ci --noservice -m "update to (${kde_new_version})"
  cd $kde_obs_dir/
  rm -rf $package
}


# Main routine. Go through the full list of packages in the KDE Application release

for i in `cat ~/openSUSE/kde-apps`
do
	echo "Updating package $i"
        case "$i" in
		        baloo5-widgets)
				git_package=baloo-widgets
				;;
	                kdebase4-runtime)
				git_package=kde-runtime
				;;
	                mobipocket)
				git_package=kdegraphics-mobipocket
				;;
	                dragonplayer)
				git_package=dragon
				;;
	                kde-mplayer-thumbnailer)
				git_package=mplayerthumbs
				;;
	                kio_audiocd)
				git_package=audiocd-kio
				;;
	                kde-print-manager)
		       	    git_package=print-manager
			    ;;
                        kdesdk4-scripts)
                            git_package=kde-dev-scripts
                            ;;
                        kdnssd)
                            git_package=zeroconf-ioslave
                            ;;
                        gwenview5)
                            git_package=gwenview
                            ;;
                        kio-extras5)
                            git_package=kio-extras
                            ;;
                        akonadi-server)
                            git_package=akonadi
                            ;;
                        kwalletmanager5)
                            git_package=kwalletmanager
                            ;;
                        khelpcenter5)
                            git_package=khelpcenter
                            ;;
                        kleopatra5)
                            git_package=kleopatra
                            ;;
	                akonadi-contact)
				git_package=akonadi-contacts
				;;
                        *)
                            git_package=`echo $i | sed s,"4","",g`
                            ;;
  esac
              submit_package $i $git_package
done

# Now tackle the KDE4 apps
#
for i in `cat ~/openSUSE/kde4-apps`
do
	echo "Updating package $i"
        case "$i" in
                        kdesdk4-scripts)
                            git_package=kde-dev-scripts
                            ;;
		        *)
                            git_package=`echo $i | sed s,"4","",g`
	  	 	    ;;
	esac
        submit_kde4_package $i $git_package
done

