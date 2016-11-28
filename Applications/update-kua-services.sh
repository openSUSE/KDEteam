#!/usr/bin/zsh

#Set variables used by this script
kde_obs_dir=~/openSUSE/KDE\:Unstable\:Applications
kde_new_version=17.03.60

submit_package() {
  # Submit package to OBS
  package=$1

 
  cd $kde_obs_dir/
  osc co $package
  cd $package

  cat _service |sed s,"16.11.60","$kde_new_version",g > /tmp/out && mv -f /tmp/out ./_service;

  # Commit the new snapshot
  osc addremove
  osc ci --noservice -m " "
  cd $kde_obs_dir/
  rm -rf $package
}

for i in `osc ls KDE:Unstable:Applications`
do 
	echo "Updating package $i"
        submit_package $i
done
