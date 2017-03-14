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
from urllib.parse import urlparse

from arghandler import ArgumentHandler, subcmd
from pyrpm.spec import Spec, replace_macros
from sarge import run, get_stdout, shell_format


VERSION_RE = re.compile(r"(^Version:\s+).*")
PATCH_RE = re.compile("(^Patch[0-9]{1,}:\s+).*")

BASE_URL = "https://www.kde.org/announcements/"
URL_MAPPING = {"plasma": "plasma-{version_to}.php",
               "frameworks": "kde-frameworks-{version_to}.php",
               "applications": "announce-applications-{version_to}.php"}

CHANGES_TEMPLATE = """
-------------------------------------------------------------------
{date} - {committer}

{contents}
"""
CHANGES_ENTRY = "  * {subject} {bugs}"


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

    # Catch the output and decode it (check_output returns bytes)

    all_commits = get_stdout(all_commits_cmd).splitlines()

    if not all_commits:
        yield "  * None"

    if len(all_commits) > 30:
        yield "  * Too many changes to list here"

    for commit in all_commits:

        subject_cmd = ["git", "show", "-s", "--pretty=format:%s", commit]
        subject = get_stdout(subject_cmd).strip()

        if "GIT_SILENT" in subject or "SVN_SILENT" in subject:
            continue

        bug_content_cmd = "git show {}".format(commit)

        bug_content = get_stdout(bug_content_cmd).splitlines()
        # Split BUG: keywords and keep only the number, replace them
        # with "kde#NNNN"
        bug_content = ["kde#{}".format(line.split(":")[1])
                       for line in bug_content if line.startswith("BUG:")]
        # Empty string if no entries, else join all bugs and wrap in ()
        bug_content = "" if not bug_content else "({})".format(
            ", ".join(bug_content))

        entry = CHANGES_ENTRY.format(subject=subject,
                                     bugs=bug_content).rstrip()

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
                         version_from: str, version_to: str, changetype: str,
                         kind: str, destination: str, committer: str) -> None:

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


def record_changes(changes_file: str, checkout_dir: str, version_from: str,
                   version_to: str, *, upstream_reponame: str,
                   changetype: str="bugfix", kind: str="applications",
                   committer: str =None, branch: str=None) -> None:

    package_name = changes_file.replace(".changes", "")
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
    code = run(command)

    return code.returncode == 0


# Spec file handling


def parse_spec(specfile: Path) -> (str, list):

    specfile = Spec.from_file(str(specfile))
    version = specfile.version
    # FIXME: Assumes Source0 is always the tarball
    upstream_source = specfile.sources[0]

    if urlparse(upstream_source).scheme:
        # URL in source: get the file name
        upstream_source = os.path.basename(urlparse(upstream_source).path)

    upstream_source = upstream_source.replace("-%{version}.tar.xz", "")
    # Expand things like %{name}
    # FIXME: Won't work for special oS macros
    upstream_source = replace_macros(upstream_source, specfile)

    patches = None if not hasattr(specfile, "patches") else specfile.patches

    return version, patches, upstream_source


def update_version(specfile: str, version_to: str, patches=None) -> None:

    with fileinput.input(specfile, inplace=True) as f:
        for line in f:
            line = line.rstrip()
            if VERSION_RE.match(line):
                line = VERSION_RE.sub(r"\g<1>" + version_to, line)
            # TODO: Do the same for patches
            print(line)


def update_package(entry: Path, version_to: str, tarball_directory: str, *,
                   committer: str, kind: str="applications",
                   changetype: str="bugfix", checkout_dir: str=None,
                   upstream_branch: str=None) -> bool:

    package_name = entry.name
    specfile = package_name + ".spec"
    # Need to keep the absolute path as we're moving elsewhere when
    # reading the checkout
    changes_file = str(Path(package_name + ".changes").absolute())

    current_version, patches, upstream_reponame = parse_spec(specfile)

    print("Updating package {}".format(package_name))

    tarball_name = "{name}-{version_to}.tar.xz".format(name=upstream_reponame,
                                                       version_to=version_to)

    tarball_directory = Path(tarball_directory)
    done_subdir = tarball_directory / "done"
    done_subdir.mkdir(exist_ok=True)

    if (done_subdir / tarball_name).exists():
        print("Tarball {} already processed, skipping".format(tarball_name))
        return False

    tarball_path = tarball_directory / tarball_name
    destination_path = entry / tarball_name

    if not tarball_path.exists():
        print("Tarball {} missing, skipping".format(tarball_name))
        return False

    shutil.copy(str(tarball_path), str(destination_path))
    tarball_path.rename(done_subdir / tarball_name)

    update_version(specfile, version_to, patches)

    record_changes(changes_file, checkout_dir, current_version,
                   version_to, upstream_reponame=upstream_reponame,
                   changetype=changetype, kind=kind, committer=committer)

    if Path("pre_checkin.sh").exists():
        run("pre_checkin.sh", shell=True)

    return True

# Command line parsing and subparsers


@subcmd
def make_changes(parser, context, args):

    parser.add_argument("--version-from", help="New version to update from")
    parser.add_argument("--version-to", help="New version to update to")
    parser.add_argument("-s", "--checkout-dir",
                        help="Directory containing source checkouts")
    parser.add_argument("-t", "--type", choices=("bugfix", "feature"),
                        help="Type of release (bugfix or feature)",
                        default="bugfix")
    parser.add_argument("-e", "--committer", required=True,
                        help="Email address of the committer")
    parser.add_argument("changes_file", help="Changes file to update")
    parser.add_argument("upstream_name", help="Upstream package name")

    options = parser.parse_args(args)
    record_changes(options.changes_file, options.checkout_dir,
                   options.version_from, options.version_to,
                   upstream_reponame=options.upstream_name,
                   committer=options.committer, branch=None)


@subcmd
def update_packages(parser, context, args):

    parser.add_argument("-t", "--type", choices=("bugfix", "feature"),
                        help="Type of release (bugfix or feature)",
                        default="bugfix")
    parser.add_argument(
        "-b", "--stable-branch",
        help="Use information from this branch if a tag is not available")
    parser.add_argument("--tarball-dir", required=True,
                        help="Directory containing source tarballs")
    parser.add_argument("-s", "--checkout-dir",
                        help="Directory containing source checkouts")
    parser.add_argument("--version-to", help="New version to update to")
    parser.add_argument("-k", "--kind", default="applications",
                        choices=("plasma", "frameworks", "applications"))
    parser.add_argument("-e", "--committer", required=True,
                        help="Email address of the committer")
    parser.add_argument("directory", help="Directory with the OBS checkout")

    options = parser.parse_args(args)

    results = Counter()

    for entry in Path(options.directory).iterdir():

        if not entry.is_dir() or entry.name.startswith("."):
            continue

        with cd(entry):
            result = update_package(entry, options.version_to,
                                    options.tarball_dir,
                                    committer=options.committer,
                                    kind=options.kind, changetype=options.type,
                                    checkout_dir=options.checkout_dir,
                                    upstream_branch=options.stable_branch)

            if result:
                results.update(["updated"])
            else:
                results.update(["failedskipped"])
        results.update(["total"])

    print("Processed {} packages: updated {}, failed/skipped {}".format(
        results["total"], results["updated"], results["failedskipped"]))


def main():

    handler = ArgumentHandler()
    handler.run()


if __name__ == "__main__":
    main()
