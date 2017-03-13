#!/usr/bin/env python3

from contextlib import contextmanager
from collections import Counter
import fileinput
import os
from pathlib import Path
import re
import shutil
import tempfile
import time
import subprocess

from arghandler import ArgumentHandler, subcmd
from pyrpm.spec import Spec


SPECIAL_CASES = ("kdelibs4", "kde-l10n")
VERSION_RE = re.compile(r"(^Version:\s+).*")
PATCH_RE = re.compile("(^Patch[0-9]{1,}:\s+).*")
PROJECT_NAMES = {"plasma": "KDE:Frameworks5",
                 "frameworks": "KDE:Frameworks5",
                 "applications": "KDE:Applications"}
BASE_URL = "https://www.kde.org/announcements/"
URL_MAPPING = {"plasma": "plasma-{version_to}.php",
               "frameworks": "kde-frameworks-{version_to}.php",
               "applications": "announce-applications-{version_to}.php"}

CHANGES_TEMPLATE = """
-------------------------------------------------------------------
{date} - {committer}

{contents}
"""


@contextmanager
def cd(subpath):
    old_path = Path.cwd()
    os.chdir(old_path / subpath)
    try:
        yield
    finally:
        os.chdir(old_path)

# Changelog handling


def format_log_entries(commit_from: str, commit_to: str) -> str:

    all_commits_cmd = ["git", "log", "--pretty=format:%H", "--no-merges",
                       "{}..{}".format(commit_from, commit_to)]

    all_commits = subprocess.check_output(all_commits_cmd)
    all_commits = all_commits.decode().split("\n")

    if not all_commits:
        return "  * None"

    if len(all_commits) > 30:
        return "- Too many changes to list here"

    for commit in all_commits:
        entry = "  * {subject} {bugs}"
        subject_cmd = ["git", "show", "-s", "--pretty=format:%s", commit]
        subject = subprocess.check_output(subject_cmd).decode().strip()

        if "GIT_SILENT" in subject or "SVN_SILENT" in subject:
            continue

        bug_content_cmd = ("git show {} | grep -E '^\s*BUG:' | "
                           "cut -d: --fields=2 | sed 's/^/,kde#/'")
        bug_content_cmd = bug_content_cmd.format(commit)
        bug_content = subprocess.check_output(bug_content_cmd, shell=True)
        bug_content = bug_content.decode()

        if not bug_content:
            bug_content = ""
        else:
            bug_content = bug_content.replace(",", "").split("\n")
            bug_content = ",".join(bug_content)
            bug_content = "({})".format(bug_content)

        entry = entry.format(subject=subject, bugs=bug_content).rstrip()

        yield entry


def create_dummy_changes_entry(version_to: str, destination: str,
                               kind: str) -> None:

    contents = "  * Update to {}".format(version_to)
    date = time.strftime("%a %d %b %H.%M.%S %Z %Y")
    url = BASE_URL + URL_MAPPING[kind].format(version_to=version_to)
    committer = ""
    changes_entry = CHANGES_TEMPLATE.format(date=date, contents=contents,
                                            committer=committer)
    with fileinput.input(destination, inplace=True) as f:
        for line in f:
            if f.isfirstline():
                print(changes_entry)
            print(line.strip())


def create_changes_entry(repo_name: str, commit_from: str, commit_to: str,
                         version_from: str, version_to: str,
                         changetype: str, kind: str, destination: str,
                         committer: str) -> None:

    url = BASE_URL + URL_MAPPING[kind].format(version_to=version_to)

    contents = list()
    contents.append("- Update to {}".format(version_to))
    contents.append("  * New {} release".format(changetype))
    contents.append("  * For more details please see:")
    contents.append("  * {}".format(url))
    contents.append("- Changes since {}:".format(version_from))

    for entry in format_log_entries(commit_from, commit_to):
        contents.append(entry)

    contents = "\n".join(contents)
    date = time.strftime("%a %d %b %H.%M.%S %Z %Y")
    changes_entry = CHANGES_TEMPLATE.lstrip()
    changes_entry = changes_entry.format(date=date, contents=contents,
                                         committer=committer)

    with fileinput.input(destination, inplace=True) as f:
        for line in f:
            if f.isfirstline():
                print(changes_entry)
            print(line.rstrip())


def record_changes(package_name: str, checkout_dir: str,
                   version_from: str, version_to: str, *,
                   upstream_reponame: str, changetype: str="bugfix",
                   kind: str="applications", changes_file: str=None,
                   committer: str =None, branch: str=None) -> None:

    commit_from = "v{}".format(version_from)
    commit_to = "v{}".format(version_to)

    upstream_repo_path = Path(checkout_dir).expanduser() / upstream_reponame

    if not upstream_repo_path.exists():
        print("Missing checkout for {}".format(upstream_reponame))
        create_dummy_changes_entry(version_to, changes_file, kind)
        return

    with cd(upstream_repo_path):

        if not upstream_tag_available(commit_to):

            if package_name == "kdelibs":
                commit_to = "KDE/4.14"
            else:
                commit_to = branch

        create_changes_entry(upstream_reponame, commit_from, commit_to,
                             version_from, version_to, changetype, kind,
                             changes_file, committer)


def upstream_tag_available(tag: str) -> bool:

    command = ("git tag -l | grep {}".format(tag))
    code = subprocess.call(command, shell=True)

    return code == 0


# Spec file handling


def get_current_version(specfile: Path) -> (str, list):
    specfile = Spec.from_file(str(specfile))
    version = specfile.version
    patches = None if not hasattr(specfile, "patches") else specfile.patches

    return version, patches


def update_version(specfile: str, version_to: str, patches=None) -> None:

    with fileinput.input(specfile, inplace=True) as f:
        for line in f:
            line = line.rstrip()
            if VERSION_RE.match(line):
                line = VERSION_RE.sub(r"\g<1>" + version_to, line)
            # TODO: Do the same for patches
            print(line)


def update_patches(specfile_source, specfile_destination):
    pass


# OBS and package update handling


def update_from_develproject(source_project, destination_project):
    pass


def update_package(package_name: str, version_to: str, tarball_directory: str,
                   obs_directory: str, *, committer: str,
                   kind: str="applications", changetype: str="bugfix",
                   checkout_dir: str=None, upstream_branch: str=None) -> bool:

    tarball_directory = Path(tarball_directory).expanduser()
    tarball_name = "{name}-{version_to}.tar.xz".format(name=package_name,
                                                       version_to=version_to)
    project_name = PROJECT_NAMES[kind]

    done_subdir = Path(tarball_directory) / "done"
    done_subdir.mkdir(exist_ok=True)

    if (done_subdir / tarball_name).exists():
        print("Tarball {} already processed, skipping".format(tarball_name))
        return False

    obs_directory = Path(obs_directory).expanduser() / package_name
    checkout_package(obs_directory)

    tarball_path = tarball_directory / tarball_name
    destination_path = obs_directory / tarball_name

    # We can safely ignore "problems" with kde-l10n as they're still in SVN
    upstream_reponame = tarball_name.replace("-{}.tar.xz".format(version_to),
                                             "")

    if not tarball_path.exists():
        print("Tarball {} missing, skipping".format(tarball_name))
        return False

    shutil.copy(str(tarball_path), str(destination_path))
    tarball_path.rename(done_subdir / tarball_name)

    with cd(obs_directory):
        specfile = package_name + ".spec"
        current_version, patches = get_current_version(specfile)
        update_version(specfile, version_to, patches)
        changes_file = str(obs_directory / (package_name + ".changes"))
        record_changes(package_name, checkout_dir, current_version,
                       version_to, upstream_reponame=upstream_reponame,
                       changetype=changetype, kind=kind,
                       changes_file=changes_file, committer=committer)
        if "kde-l10n" in package_name:
            subprocess.call("pre_checkin.sh", shell=True)

    return True


def checkout_package(obs_package_dir: Path) -> None:

    if obs_package_dir.exists():
        with cd(obs_package_dir):
            subprocess.check_call(["osc", "up"])
    else:
        with cd(obs_package_dir.parent):
            subprocess.check_call(["osc", "co", obs_package_dir.name])

# Command line parsing and subparsers


@subcmd
def update_packages(parser, context, args):

    parser.add_argument("-t", "--type", choices=("bugfix", "feature"),
                        help="Type of release (bugfix or feature)",
                        default="bugfix")
    parser.add_argument("-p", "--project-dir", required=True,
                        help="OBS project checkout directory")
    parser.add_argument(
        "-b", "--stable-branch",
        help="Use information from this branch if a tag is not available")
    parser.add_argument("--tarball-dir", required=True,
                        help="Directory containing source tarballs")
    parser.add_argument("-s", "--checkout-dir",
                        help="KDE source checkout directory (optional)")
    parser.add_argument("--version-to",
                        help="New version to update to")
    parser.add_argument("-k", "--kind", default="applications",
                        choices=("plasma", "frameworks", "applications"))
    parser.add_argument("-e", "--committer", default="", required=True,
                        help="Email address of the committer")
    parser.add_argument("packagelist", nargs="+",
                        help="File(s) with package lists")

    options = parser.parse_args(args)

    results = Counter()

    for filename in options.packagelist:
        with open(filename) as handle:
            for line in handle:
                name = line.strip()
                result = update_package(name, options.version_to,
                                        options.tarball_dir,
                                        options.project_dir,
                                        committer=options.committer,
                                        kind=options.kind, type=options.type,
                                        checkout_dir=options.checkout_dir,
                                        upstream_branch=options.stable_branch)
                if result:
                    results.update(["updated"])
                else:
                    results.update(["failedskipped"])

    print("Processed {} packages: updated {}, failed/skipped {}".format(
        results["updated"], results["failedskipped"]))


@subcmd
def update_source_services(parser, context, args):
    pass


def main():

    handler = ArgumentHandler()
    handler.run()


if __name__ == "__main__":
    main()
