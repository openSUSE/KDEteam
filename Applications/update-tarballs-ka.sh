#!/usr/bin/zsh
set -e 
setopt nounset
unsetopt nomatch

#Set variables used by this script
kde_sources=~/openSUSE/KDE
kde_obs_dir=~/openSUSE/home\:luca_b\:test_KA
kde_new_version=16.12.1
kdelibs_new_version=4.14.28

submit_package() {
  # Submit package to OBS
  package=$1
  src_pack=$2

  # Skip previously done tarballs

  if [ $package == "kdelibs4" ];
  then
      packagefile="${src_pack}-$kdelibs_new_version.tar.xz"
  else
      packagefile="${src_pack}-$kde_new_version.tar.xz"
  fi

  if [ ! -f $packagefile ] && [ -f $kde_sources/done/$packagefile ];
  then
    echo "Skipping $src_pack, already done"
    return
  fi


  cd $kde_obs_dir/
  osc co $package
  cd $package

  # Determine current version
  kde_sem_version=`grep 'Version:' ${package}.spec | awk {'print $2'}`

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
        submit_package $i $git_package
done

