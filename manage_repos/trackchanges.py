#!/usr/bin/env python3

from contextlib import contextmanager
from collections import defaultdict
import fileinput
import os
from pathlib import Path
import re
import shutil
import tempfile
import time
from urllib.parse import urlparse

from sarge import run, get_stdout, shell_format

__all__ = ["record_changes", "cd"]

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


def _add_patch_information(contents: list, patches: list, text: str=None):

    if not patches or not contents:
        return

    contents.append(text)
    for patch in patches:
        contents.append(CHANGES_ENTRY.format(subject=patch, bugs=""))


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

    assert commit_to is not None

    all_commits_cmd = ["git", "log", "--pretty=format:%H", "--no-merges",
                       "{}..{}".format(commit_from, commit_to)]

    all_commits = get_stdout(all_commits_cmd).splitlines()

    if not all_commits:
        yield "  * None"
        return

    if len(all_commits) > 30:
        yield "  * Too many changes to list here"
        return

    for commit in all_commits:

        subject_cmd = ["git", "show", "-s", "--pretty=format:%s", commit]
        subject = get_stdout(subject_cmd).strip()

        if "GIT_SILENT" in subject or "SVN_SILENT" in subject:
            continue

        bug_content_cmd = "git show -s {}".format(commit)
        bug_content = get_stdout(bug_content_cmd).splitlines()
        bug_content = [line.strip() for line in bug_content if line.strip()]

        # Split BUG: keywords and keep only the number, replace them
        # with "kde#NNNN"
        bug_content = ["kde#{}".format(line.split(":")[1].strip())
                       for line in bug_content
                       if line.startswith("BUG:")]
        # Empty string if no entries, else join all bugs and wrap in ()
        bug_content = "" if not bug_content else "({})".format(
            ", ".join(bug_content))

        entry = CHANGES_ENTRY.format(subject=subject,
                                     bugs=bug_content).rstrip()

        yield entry


def create_dummy_changes_entry(version_to: str, destination: str,
                               kind: str, committer: str) -> None:

    contents = "  * Update to {}".format(version_to)
    date = time.strftime("%a %b %d %H:%M:%S %Z %Y")
    changes_entry = CHANGES_TEMPLATE.format(date=date, contents=contents,
                                            committer=committer)
    with fileinput.input(destination, inplace=True) as f:
        for line in f:
            if f.isfirstline():
                print(changes_entry)
            print(line.rstrip())


def create_changes_entry(repo_name: str, commit_from: str, commit_to: str,
                         version_from: str, version_to: str, changetype: str,
                         kind: str, destination: str, committer: str,
                         previous_patches: list=None,
                         current_patches: list=None) -> None:

    contents = list()
    contents.append("- Update to {}".format(version_to))
    contents.append("  * New {} release".format(changetype))

    if kind != "other":
        url = BASE_URL + URL_MAPPING[kind].format(version_to=version_to)
        contents.append("  * For more details please see:")
        contents.append("  * {}".format(url))

    contents.append("- Changes since {}:".format(version_from))

    commit_data = list()

    for entry in format_log_entries(commit_from, commit_to):
        commit_data.append(entry)

    if not commit_data:
        contents.append("  * None")
    else:
        contents.extend(commit_data)

    if current_patches and previous_patches:
        patches_difference = set(current_patches) - set(previous_patches)
    else:
        patches_difference = set()

    if patches_difference:

        added_patches = list()
        removed_patches = list()

        print("Patches changed.")
        print("The program will record these changes, but this will require"
              " MANUAL REVIEW. Their nature cannot be guessed automatically.")

        for patch in patches_difference:
            if patch in current_patches:
                added_patches.append(patch)
            elif patch in previous_patches:
                removed_patches.append(patch)

        _add_patch_information(contents, added_patches, "- Added patches:")
        _add_patch_information(contents, added_patches, "- Removed patches:")

    contents = "\n".join(contents)
    date = time.strftime("%a %b %d %H:%M:%S %Z %Y")
    changes_entry = CHANGES_TEMPLATE.lstrip()
    changes_entry = changes_entry.format(date=date, contents=contents,
                                         committer=committer)

    with fileinput.input(destination, inplace=True) as f:
        for line in f:
            if f.isfirstline():
                print(changes_entry)
            print(line.rstrip())


def record_changes(changes_file: str, checkout_dir: Path, version_from: str,
                   version_to: str, *, upstream_reponame: str,
                   changetype: str="bugfix", kind: str="applications",
                   committer: str=None, branch: str=None,
                   **kwargs) -> None:

    # Strip path name
    package_name = Path(changes_file.replace(".changes", "")).name
    package_name = str(package_name)

    commit_from = "v{}".format(version_from)
    commit_to = "v{}".format(version_to)

    if checkout_dir is None:
        print("No checkout directory supplied for {}".format(
            upstream_reponame))
        create_dummy_changes_entry(version_to, changes_file, kind,
                                   committer)
        return

    upstream_repo_path = checkout_dir / upstream_reponame

    if not upstream_repo_path.exists():
        print("Missing checkout for {}".format(upstream_reponame))
        create_dummy_changes_entry(version_to, changes_file, kind,
                                   committer)
        return

    with cd(upstream_repo_path):

        # Switch to the branch to get up to date information
        if branch is not None and branch != "master":
            branch = "KDE/4.14" if package_name == "kdelibs4" else branch
            cmd = run(["git", "checkout", branch])

        if not upstream_tag_available(commit_to):

            if package_name == "kdelibs4":
                commit_to = "KDE/4.14"
            else:
                commit_to = branch

        create_changes_entry(upstream_reponame, commit_from, commit_to,
                             version_from, version_to, changetype, kind,
                             changes_file, committer, **kwargs)


def upstream_tag_available(tag: str) -> bool:

    command = ("git tag -l | grep {}".format(tag))
    code = run(command)

    return code.returncode == 0
