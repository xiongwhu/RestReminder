#!/usr/bin/env python3
# SPDX-License-Identifier: CPAL-1.0
# The contents of this file are subject to the Common Public Attribution License Version 1.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at https://opensource.org/license/cpal-1-0. The License is based on the Mozilla Public License Version 1.1 but Sections 14 and 15 have been added to cover use of software over a computer network and provide for limited attribution for the Original Developer. In addition, Exhibit A has been modified to be consistent with Exhibit B.
#
# Software distributed under the License is distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for the specific language governing rights and limitations under the License.
#
# The Original Code is RestReminder (歇一会儿), including the original source code, tests and build scripts distributed in this repository. Third-party photographs identified in Resources/PHOTO-CREDITS.md are excluded and remain subject to their original licenses.
# The Initial Developer of the Original Code is 广州迈润网络科技有限公司 (迈润智人 RaCIO).
# The Original Developer is the Initial Developer.
# All portions of the code written by the Initial Developer are Copyright (c) 2026 广州迈润网络科技有限公司. All Rights Reserved.
# Contributor(s): see individual source notices and project history.
# No alternative license is designated for the Original Code.
# Attribution information: see Exhibit B in the repository LICENSE.

"""Package a preverified Universal app and the exact staged Git source tree; never launch it."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
DENIED_PARTS = {"build", ".git", ".build", ".cache", "__pycache__", "credentials", "secrets"}
DENIED_SUFFIXES = {".p12", ".pfx", ".pem", ".key", ".cer", ".crt", ".der", ".mobileprovision", ".provisionprofile", ".keystore", ".jks"}
DENIED_PHOTOS = {"Resources/morning-light.jpg", "Resources/fresh-leaves.jpg"}


class ReleaseError(Exception):
    pass


def run(arguments):
    process = subprocess.run(arguments, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if process.returncode:
        # Do not echo tool output, environment values, source blobs or local absolute paths.
        raise ReleaseError(f"{Path(arguments[0]).name} failed (exit {process.returncode}); check prerequisites and staged inputs")
    return process.stdout


def git(*arguments):
    return run(["git", *arguments])


def forbidden(name):
    path = PurePosixPath(name)
    lower = [part.lower() for part in path.parts]
    basename = path.name.lower()
    return (path.is_absolute() or ".." in path.parts or any(part in DENIED_PARTS for part in lower)
            or name in DENIED_PHOTOS or path.suffix.lower() in DENIED_SUFFIXES
            or basename.startswith((".env", "id_rsa", "id_ed25519", "id_ecdsa", "credentials.", "secrets."))
            or basename in {"instance.lock", "keychain", "login.keychain-db", ".netrc", ".npmrc", ".pypirc", ".git-credentials",
                            "auth.json", "token.json", "tokens.json", "credentials", "secret", "secrets"}
            or basename.startswith("secret.")
            or (path.suffix.lower() in {".json", ".plist", ".csv"} and any(word in basename for word in ("history", "preferences", "defaults"))))


def parse_entries(data):
    entries = []
    for entry in data.split(b"\0"):
        if not entry:
            continue
        metadata, raw_name = entry.split(b"\t", 1)
        name = raw_name.decode("utf-8")
        if metadata.split()[0] not in {b"100644", b"100755"} or forbidden(name):
            raise ReleaseError("Source index contains a forbidden path, nonregular file, signing credential or private-data filename; values withheld")
        entries.append(name)
    return entries


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def verify_plist(path, expected, version):
    with path.open("rb") as source:
        actual = plistlib.load(source)
    for key in ("CFBundleIdentifier", "CFBundleVersion", "CFBundleExecutable"):
        if actual.get(key) != expected.get(key):
            raise ReleaseError(f"App plist differs from staged source: {key}")
    if actual.get("CFBundleShortVersionString") != version:
        raise ReleaseError("App version differs from VERSION")
    minima = actual.get("LSMinimumSystemVersionByArchitecture", {})
    if (not isinstance(minima, dict) or set(minima) != {"arm64", "x86_64"}
            or any(not isinstance(value, str) or not re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", value) for value in minima.values())):
        raise ReleaseError("Require the preverified Universal app with numeric minima for both architectures in its plist")
    return actual


def main():
    parser = argparse.ArgumentParser(description=__doc__, epilog="First run build.sh --verify-only on the original isolated app. This helper checks the copied plist/signature; it does not build, launch, notarize, or verify binary architecture/minimum targets.")
    parser.add_argument("--app", type=Path, required=True, help="Existing isolated Universal .app, already checked with build.sh --verify-only")
    args = parser.parse_args()
    try:
        prepare(args.app)
    except (ReleaseError, OSError, ValueError, plistlib.InvalidFileException, zipfile.BadZipFile) as error:
        if isinstance(error, ReleaseError):
            parser.exit(1, f"error: {error}\n")
        parser.exit(1, f"error: packaging input or output failure ({type(error).__name__}); no cleanup performed\n")


def prepare(app_argument):
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", version):
        raise ReleaseError("VERSION must contain a numeric major.minor.patch version")
    if Path(git("rev-parse", "--show-toplevel").decode().strip()).resolve() != ROOT:
        raise ReleaseError("Require a Git repository rooted at this project")
    index = git("ls-files", "--stage", "-z")
    if not index:
        raise ReleaseError("Git index is empty; stage the reviewed publication files first")
    if any(entry and entry.split(b"\t", 1)[0].split()[-1] != b"0" for entry in index.split(b"\0")):
        raise ReleaseError("Resolve unmerged index entries before packaging")
    entries = parse_entries(index)
    dirty = subprocess.run(["git", "diff", "--quiet", "--ignore-submodules=none"], cwd=ROOT,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if dirty.returncode:
        raise ReleaseError("Unstaged tracked changes or Git comparison failure; stage the reviewed files first")
    if git("ls-files", "--others", "--exclude-standard", "-z"):
        raise ReleaseError("Untracked nonignored files remain; review and stage or ignore them first")
    required = {"VERSION", "Info.plist", "LICENSE", "Resources/PHOTO-CREDITS.md", "build.sh", "README.md"}
    if not required.issubset(entries):
        raise ReleaseError("Required source publication inputs are missing from the index")
    tree = git("write-tree").decode().strip()
    if git("show", f"{tree}:VERSION").decode().strip() != version:
        raise ReleaseError("Staged VERSION differs from the working copy")
    expected = plistlib.loads(git("show", f"{tree}:Info.plist"))
    if expected.get("CFBundleShortVersionString") != version:
        raise ReleaseError("Staged Info.plist app version differs from VERSION")
    app = app_argument.expanduser().resolve()
    if not app.is_dir() or app.suffix != ".app":
        raise ReleaseError("--app must identify an existing isolated .app directory")
    verify_plist(app / "Contents/Info.plist", expected, version)
    for tool in ("/usr/bin/ditto", "/usr/bin/codesign"):
        if not Path(tool).is_file():
            raise ReleaseError(f"Required macOS tool is unavailable: {Path(tool).name}")
    release_root = ROOT / "build/release"
    if not release_root.resolve().is_relative_to(ROOT / "build"):
        raise ReleaseError("Release output escapes the project build directory")
    release_root.mkdir(parents=True, exist_ok=True)
    output = release_root / f"v{version}"
    if output.exists():
        raise ReleaseError("Version output directory already exists; inspect existing artifacts before another run")
    output.mkdir()
    staging = Path(tempfile.mkdtemp(prefix=f".staging-v{version}-", dir=release_root))
    distribution = staging / f"RestReminder-{version}"
    distribution.mkdir()
    source_name = f"RestReminder-{version}-source.zip"
    binary_name = f"RestReminder-{version}-macos-universal-ad-hoc.zip"
    source_zip, binary_zip = output / source_name, output / binary_name
    prefix = f"RestReminder-{version}/"
    git("archive", "--format=zip", f"--prefix={prefix}", f"--output={source_zip}", tree)
    with zipfile.ZipFile(source_zip) as archive:
        names = {name for name in archive.namelist() if not name.endswith("/")}
        if names != {prefix + name for name in entries} or archive.testzip() is not None:
            raise ReleaseError("Source archive differs from index or failed integrity checking; check export-ignore attributes")
    shutil.copyfile(source_zip, distribution / source_name)
    staged_app = distribution / app.name
    run(["/usr/bin/ditto", str(app), str(staged_app)])
    notice = (f"RestReminder {version} — Corresponding Source\n\n"
              "The covered source code is available under CPAL-1.0.\n"
              f"Exact Git source tree: {tree}\n"
              f"Corresponding source archive: {source_name}\n\n"
              "That source archive is provided alongside the application in the same original distribution.\n"
              "It contains the complete staged project source, tests, build scripts, documentation and license.\n"
              "Extract it and follow README.md and RELEASING.md, when present, to build or modify the app.\n"
              "Third-party photographs retain their separate licenses; see PHOTO-CREDITS.md.\n")
    resources = staged_app / "Contents/Resources"
    if not resources.is_dir() or resources.is_symlink():
        raise ReleaseError("Copied app Resources directory is missing or is a symlink")
    notice_path = resources / "SOURCE-CODE.txt"
    if notice_path.is_symlink():
        raise ReleaseError("Copied app source notice must not be a symlink")
    notice_path.write_text(notice, encoding="utf-8")
    (distribution / "SOURCE-CODE.txt").write_text(notice, encoding="utf-8")
    for destination, source in (("LICENSE", "LICENSE"), ("PHOTO-CREDITS.md", "Resources/PHOTO-CREDITS.md")):
        content = git("show", f"{tree}:{source}")
        (distribution / destination).write_bytes(content)
        resource = resources / destination
        if resource.is_symlink():
            raise ReleaseError("Copied app license or photo credits must not be a symlink")
        resource.write_bytes(content)
    (distribution / "RELEASE-INSTRUCTIONS.txt").write_text(
        f"RestReminder {version}\n\n"
        "This is a local ad-hoc signed build, without Developer ID signing or Apple notarization.\n"
        "Move the app to a fixed Applications location before configuring login startup and permissions.\n"
        "Review the included source README for system requirements, permissions and validation limits.\n"
        f"To build: extract {source_name}, enter RestReminder-{version}, and run ./build.sh.\n"
        "The app and source are distributed together. Keep SOURCE-CODE.txt, LICENSE and photo credits.\n",
        encoding="utf-8")
    run(["/usr/bin/codesign", "--force", "--sign", "-", str(staged_app)])
    run(["/usr/bin/codesign", "--verify", "--all-architectures", "--deep", "--strict", str(staged_app)])
    signature = subprocess.run(["/usr/bin/codesign", "--display", "--verbose=4", str(staged_app)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if signature.returncode or b"Signature=adhoc" not in signature.stdout + signature.stderr:
        raise ReleaseError("Copied app must have a valid ad-hoc signature")
    staged_plist = verify_plist(staged_app / "Contents/Info.plist", expected, version)
    run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(distribution), str(binary_zip)])
    with zipfile.ZipFile(binary_zip) as archive:
        if archive.testzip() is not None:
            raise ReleaseError("Application distribution ZIP failed integrity checking")
    artifacts = {name: {"sha256": digest(output / name), "bytes": (output / name).stat().st_size} for name in (source_name, binary_name)}
    manifest = {
        "version": version, "app_build": str(staged_plist["CFBundleVersion"]),
        "source_git_tree": tree, "source_file_count": len(entries), "source_prefix": prefix,
        "license": "CPAL-1.0", "signature": "ad-hoc", "notarized": False,
        "declared_minimum_system_versions": staged_plist["LSMinimumSystemVersionByArchitecture"],
        "validation": "Copied plist and all-architecture signature checked; original binary architectures/minimum targets require build.sh --verify-only before packaging.",
        "created_utc": datetime.now(timezone.utc).isoformat(), "artifacts": artifacts,
    }
    manifest_path = output / "release-manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    checksummed = [source_zip, binary_zip, manifest_path]
    (output / "SHA256SUMS").write_text("".join(f"{digest(path)}  {path.name}\n" for path in checksummed), encoding="utf-8")
    print(f"PASS: {len(entries)} staged source files, tree {tree}, version {version}, copied app plist/ad-hoc signature, both ZIPs and SHA256SUMS")
    print(output.relative_to(ROOT).as_posix())
    print("Unique staging copy retained; no source app changes, launch, cleanup, commit or push performed.")


if __name__ == "__main__":
    main()
