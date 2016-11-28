#!/usr/bin/zsh

#Set variables used by this script
kde_obs_dir=~/openSUSE/KDE\:Unstable\:Applications

usage() {

  echo "Usage is as follows:"
  echo
  echo "$PROGRAM <old-version> <new-version>"
  echo
  echo
}

submit_package() {
  # Submit package to OBS
  package=$1

 
  cd $kde_obs_dir/
  osc co $package
  cd $package

  sed -i s/$kde_old_version/$kde_new_version/ _services

  # Commit the new snapshot
  osc addremove
  osc ci --noservice -m " "
  cd $kde_obs_dir/
  rm -rf $package
}

if [[ "$#" -ne 2 ]]; then
	usage
	exit
fi

kde_old_version=$1
kde_new_version=$2

for i in `osc ls KDE:Unstable:Applications`
do 
	echo "Updating package $i"
        submit_package $i
done
