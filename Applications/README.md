Scripts related to KDE:Applications and KDE:Unstable:Applications repositories

All scripts here will assume that the openSUSE OBS repository local downloads are located in:
~/openSUSE/OBS/<repository>

If this directory is not present, then either adjust the scripts to use a different directory or create it :)


The update script is used to update the versions used for the KDE Applications in the KUA repository.
Before running one should adjust the old and new versions. It will then download package by package and update the version in the _service file. After commiting it to OBS, it will remove the package from the local directory

The update-apps.sh script is used to upload quickly the new KDE Application releases (exchange tarball, update version in spec-file and create a changelog entry). 
For this to work the following conditions must be met:
- Use zsh, so that one can create the required changelog entry with the -m.. command. I will also update the  .zshrc file for this one.
- The script has a couple of variables defined (e.g. new version, tarball location, etc). It also assumes that there is a "done" directory in the tarball location directory where it can move the file after completion.
- The file kde-apps is used as a reference which packages we have on OBS. If a new package has been released, this is easy noticable as that it is untouched in the tarball location (not moved to done). 

