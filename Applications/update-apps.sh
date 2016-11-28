#!/usr/bin/zsh
set -e
setopt nounset

#Set variables used by this script
kde_sources=~/openSUSE/1608
kde_obs_dir=~/openSUSE/KDE\:Applications
kde_new_version=16.12.0
kdelibs_new_version=4.14.24
OLDPATCH=/tmp/patches.old
NEWPATCH=/tmp/patches.new
DIFFPATCH=/tmp/patches.diff

submit_package() {
  # Submit package to OBS
  package=$1
  src_pack=$2

  cd $kde_obs_dir/
  osc co $package
  cd $package

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

  # Validate for dropped or new patches
  diff ${OLDPATCH} ${NEWPATCH} > ${DIFFPATCH}
  dropped=`cat ${DIFFPATCH} | grep '^<' | awk {'print $2'}`
  added=`cat ${DIFFPATCH} | grep '^>' | awk {'print $2' }`

  # Drop removed patches
  for i in `echo $dropped`
  do
	  rm $i
  done

  # Retrieve new patches
  for i in `echo $added`
  do
	  osc co KDE:Unstable:Applications ${package}.spec $i
  done

  # Remove old tarball and add new one
  case "$package" in 
              kdelibs4)
                      rm ${src_pack}-${kde_cur_version}.tar.xz
                      cp ${kde_sources}/${src_pack}-${kdelibs_new_version}.tar.xz .
                      mv ${kde_sources}/${src_pack}-${kdelibs_new_version}.tar.xz ${kde_sources}/done/
                      ;;
              kde-l10n)
                      rm ${src_pack}-*-${kde_cur_version}.tar.xz
                      cp ${kde_sources}/${src_pack}-*-${kde_new_version}.tar.xz .
                      mv ${kde_sources}/${src_pack}-*-${kde_new_version}.tar.xz ${kde_sources}/done/
                      ;;
              *)
                      rm ${src_pack}-${kde_cur_version}.tar.xz
                      cp ${kde_sources}/${src_pack}-${kde_new_version}.tar.xz .
                      mv ${kde_sources}/${src_pack}-${kde_new_version}.tar.xz ${kde_sources}/done/
                      ;;
  esac
  
  # Create a proper changelog for the patches
  NEWLINE=$'\n'
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

  # Update the spec file
  case "$package" in 
              kdelibs4)
		      sed -i "s/$kde_sem_version/$kdelibs_new_version/g" ${package}.spec
                      sh ./pre_checkin.sh;
                      osc vc $package.changes -m"${CHANGELIBLOG}${changes}" ;
                      osc vc -e
                      ;;
              kde-l10n)
		      sed -i "s/$kde_sem_version/$kde_new_version/g" ${package}.spec.in
                      sh ./pre_checkin.sh;
                      osc vc $package.changes -m"${CHANGELOG}$changes";
                      ;;
              *)
		      sed -i "s/$kde_sem_version/$kde_new_version/g" ${package}.spec
                      osc vc $package.changes -m"${CHANGELOG}$changes";
	       ;;
  esac

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
	                kdebase4)
				git_package=kde-baseapps
				;;
	                kdebase4-workspace)
				git_package=kde-workspace
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
