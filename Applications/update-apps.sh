#!/usr/bin/zsh

#Set variables used by this script
kde_sources=~/openSUSE/1608
kde_obs_dir=~/openSUSE/OBS/KDE\:Applications
kde_new_version=16.08.0
kdelibs_new_version=4.14.23

submit_package() {
  # Submit package to OBS
  package=$1
  src_pack=$2

 
  cd $kde_obs_dir/
  osc co $package
  cd $package

  # Determine current version 
  kde_cur_version=`cat ${package}.spec | grep 'Version:' | awk {'print $2'}`

  # Validate if update is required

            echo "Updating ${package} from $kde_cur_version to $kde_new_version"
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

            # Update the spec file
            case "$package" in 
	                kdebindings4)
                                cat ${package}.spec.in |sed s,"$kde_cur_version","$kde_new_version",g > /tmp/out && mv -f /tmp/out ./${package}.spec.in;
	                        sh ./pre_checkin.sh;
                                osc vc $package.changes -m$CHANGELOG
		                ;;
                        python-kde4)
                                cat ${package}.spec |sed s,"$kde_cur_version","$kde_new_version",g > /tmp/out && mv -f /tmp/out ./${package}.spec;
              		        sh ./pre_checkin.sh;
                                osc vc $package.changes -m$CHANGELOG
                                ;;
                        kdelibs4)
                                cat ${package}.spec |sed s,"$kde_cur_version","$kdelibs_new_version",g > /tmp/out && mv -f /tmp/out ./${package}.spec;
              		        sh ./pre_checkin.sh;
                                osc vc $package.changes -m$CHANGELIBLOG ;
                                osc vc -e
                                ;;
                        kde-l10n)
                                cat ${package}.spec.in |sed s,"$kde_cur_version","$kde_new_version",g > /tmp/out && mv -f /tmp/out ./${package}.spec.in;
              		        sh ./pre_checkin.sh;
                                osc vc $package.changes -m$CHANGELOG
                                ;;
                        *)
                                cat ${package}.spec |sed s,"$kde_cur_version","$kde_new_version",g > /tmp/out && mv -f /tmp/out ./${package}.spec;
                                osc vc $package.changes -m$CHANGELOG
		                ;;
            esac

            # Commit the new snapshot
            osc addremove
            osc ci --noservice -m "update to (${kde_new_version})"
            cd $kde_obs_dir/
            rm -rf $package
}


#Update now the packages based in GIT and submit to OBS

for i in `cat ~/openSUSE/kde-apps`
do 
	echo "Updating package $i"
        case "$i" in 
		        baloo5-widgets)
				git_package=baloo-widgets
				;;
		        plasma-addons)
				git_package=kdeplasma-addons
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
	                kdebindings-smokegen)
				git_package=smokegen
				;;
	                kdebindings-smokeqt)
				git_package=smokeqt
				;;
	                kdebindings-smokekde)
				git_package=smokekde
				;;
	                mono-qt4)
				git_package=qyoto
				;;
	                mono-kde4)
				git_package=kimono
				;;
	                python-kde4)
				git_package=pykde4
				;;
	                ruby-qt4)
				git_package=qtruby
				;;
	                ruby-kde4)
				git_package=korundum
				;;
	                perl-qt4)
				git_package=perlqt
				;;
	                perl-kde4)
				git_package=perlkde
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
	                libnepomukwidgets)
				git_package=nepomuk-widgets
				;;
	                oxygen-icon-theme)
		       	    git_package=oxygen-icons
			    ;;
	                kdebase4-artwork)
		       	    git_package=kde-base-artwork
			    ;;
	                kdebase4-wallpapers)
		       	    git_package=kde-wallpapers
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
                        gpgmepp5)
                            git_package=gpgmepp
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
