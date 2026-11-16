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


def run_process(arguments, *, timeout=120):
    try:
        return subprocess.run(arguments, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        raise ReleaseError(f"{Path(arguments[0]).name} timed out after {timeout} seconds; inspect retained staging before retrying") from error


def run(arguments, *, timeout=120):
    process = run_process(arguments, timeout=timeout)
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


def require_tools(*, dmg=False):
    tools = ["/usr/bin/ditto", "/usr/bin/codesign"]
    if dmg:
        tools.append("/usr/bin/hdiutil")
    for tool in tools:
        if not Path(tool).is_file():
            raise ReleaseError(f"Required macOS tool is unavailable: {Path(tool).name}")


def dmg_instructions(version, tree, source_name, app_name):
    return (
        f"歇一会儿 RestReminder {version} — 安装与源码说明\n\n"
        "1. 安装前，请从菜单栏退出正在运行的旧版“歇一会儿”。\n"
        f"2. 将“{app_name}”拖到本磁盘窗口的 Applications 链接，安装到“应用程序”。\n"
        "3. 从“应用程序”打开应用，按需配置登录启动和音频隐私权限。\n"
        "4. 此包只有本地 ad-hoc 签名，未使用 Developer ID，也未完成 Apple 公证。\n"
        "   首次打开若被系统阻止，请先核对下载来源与 SHA256SUMS。确认可信后，\n"
        "   可到“系统设置 → 隐私与安全性”查看针对本应用的拦截提示，并按系统提供的\n"
        "   “仍要打开”等选项确认；不同 macOS 版本的按钮与可用步骤可能不同。\n"
        "   若没有允许选项，请保留系统保护，参考随附源码自行构建或等待正式签名版本。\n"
        "   请勿关闭全局 Gatekeeper 或全局系统安全保护。\n\n"
        f"应用版本：{version}\n精确 Git source tree：{tree}\n"
        f"对应源码：{source_name}\n"
        f"构建方式：解压源码，进入 RestReminder-{version}，按 README.md 运行 ./build.sh。\n"
        "本应用与对应源码一同提供；请保留 SOURCE-CODE.txt、LICENSE 与 PHOTO-CREDITS.md。\n"
        "项目源码适用 CPAL-1.0，第三方照片继续遵守各自许可；兼容性和验证范围见源码文档。\n"
    )


def create_dmg(distribution, staging, destination, version, tree, source_name, app_name):
    if destination.exists() or destination.is_symlink():
        raise ReleaseError("DMG output already exists; inspect existing artifacts before another run")
    # A second copy keeps the installation link and DMG-specific instructions out of the ZIP.
    dmg_root = staging / "dmg-root"
    if dmg_root.exists() or dmg_root.is_symlink():
        raise ReleaseError("DMG staging directory already exists; inspect retained staging before retrying")
    run(["/usr/bin/ditto", str(distribution), str(dmg_root)])
    applications = dmg_root / "Applications"
    if applications.exists() or applications.is_symlink():
        raise ReleaseError("DMG staging already contains an Applications entry")
    applications.symlink_to("/Applications", target_is_directory=True)
    (dmg_root / "RELEASE-INSTRUCTIONS.txt").write_text(
        dmg_instructions(version, tree, source_name, app_name), encoding="utf-8")
    # HFS+ keeps the installer readable on the supported macOS versions and
    # avoids depending on a newer host's default disk-image filesystem.
    run(["/usr/bin/hdiutil", "create", "-srcfolder", str(dmg_root),
         "-volname", f"RestReminder {version}", "-fs", "HFS+", "-format", "UDZO", str(destination)], timeout=600)
    run(["/usr/bin/hdiutil", "verify", str(destination)], timeout=300)
    information = plistlib.loads(run(["/usr/bin/hdiutil", "imageinfo", "-plist", str(destination)]))
    if not isinstance(information, dict):
        raise ReleaseError("DMG image information must be a property-list dictionary")
    properties = information.get("Properties", {})
    if (information.get("Format") != "UDZO" or not isinstance(properties, dict)
            or properties.get("Compressed") is not True):
        raise ReleaseError("DMG must be a compressed read-only UDZO image")
    # UDZO is intrinsically read-only. Current hdiutil omits a writable property;
    # reject an explicit conflicting property when an older host reports one.
    if any(container[key] is not False for container in (information, properties)
           for key in ("Writeable", "Writable") if key in container):
        raise ReleaseError("DMG must be a compressed read-only UDZO image")


def main():
    parser = argparse.ArgumentParser(description=__doc__, epilog="First run build.sh --verify-only on the original isolated app. This helper checks the copied plist/signature; it does not build, launch, notarize, or verify binary architecture/minimum targets.")
    parser.add_argument("--app", type=Path, required=True, help="Existing isolated Universal .app, already checked with build.sh --verify-only")
    parser.add_argument("--dmg", action="store_true", help="Also create and verify a compressed read-only DMG with a drag-to-Applications link")
    args = parser.parse_args()
    try:
        prepare(args.app, dmg=args.dmg)
    except (ReleaseError, OSError, ValueError, plistlib.InvalidFileException, zipfile.BadZipFile) as error:
        if isinstance(error, ReleaseError):
            parser.exit(1, f"error: {error}\n")
        parser.exit(1, f"error: packaging input or output failure ({type(error).__name__}); no cleanup performed\n")


def prepare(app_argument, *, dmg=False):
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
    dirty = run_process(["git", "diff", "--quiet", "--ignore-submodules=none"])
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
    require_tools(dmg=dmg)
    release_root = ROOT / "build/release"
    if not release_root.resolve().is_relative_to(ROOT / "build"):
        raise ReleaseError("Release output escapes the project build directory")
    release_root.mkdir(parents=True, exist_ok=True)
    output = release_root / f"v{version}"
    if output.exists() or output.is_symlink():
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
    signature = run_process(["/usr/bin/codesign", "--display", "--verbose=4", str(staged_app)])
    if signature.returncode or b"Signature=adhoc" not in signature.stdout + signature.stderr:
        raise ReleaseError("Copied app must have a valid ad-hoc signature")
    staged_plist = verify_plist(staged_app / "Contents/Info.plist", expected, version)
    run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(distribution), str(binary_zip)])
    with zipfile.ZipFile(binary_zip) as archive:
        if archive.testzip() is not None:
            raise ReleaseError("Application distribution ZIP failed integrity checking")
    artifact_paths = [source_zip, binary_zip]
    if dmg:
        disk_image = output / f"RestReminder-{version}-macos-universal.dmg"
        create_dmg(distribution, staging, disk_image, version, tree, source_name, app.name)
        artifact_paths.append(disk_image)
    artifacts = {path.name: {"sha256": digest(path), "bytes": path.stat().st_size} for path in artifact_paths}
    manifest = {
        "version": version, "app_build": str(staged_plist["CFBundleVersion"]),
        "source_git_tree": tree, "source_file_count": len(entries), "source_prefix": prefix,
        "license": "CPAL-1.0", "signature": "ad-hoc", "notarized": False,
        "declared_minimum_system_versions": staged_plist["LSMinimumSystemVersionByArchitecture"],
        "validation": "Copied plist and all-architecture signature checked; original binary architectures/minimum targets require build.sh --verify-only before packaging.",
        "created_utc": datetime.now(timezone.utc).isoformat(), "artifacts": artifacts,
    }
    if dmg:
        manifest["disk_image"] = {"format": "UDZO", "compressed": True, "read_only": True, "verified": True}
    manifest_path = output / "release-manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    checksummed = [*artifact_paths, manifest_path]
    (output / "SHA256SUMS").write_text("".join(f"{digest(path)}  {path.name}\n" for path in checksummed), encoding="utf-8")
    extra = ", verified compressed read-only DMG" if dmg else ""
    print(f"PASS: {len(entries)} staged source files, tree {tree}, version {version}, copied app plist/ad-hoc signature, both ZIPs{extra} and SHA256SUMS")
    print(output.relative_to(ROOT).as_posix())
    print("Unique staging copy retained; no source app changes, launch, cleanup, commit or push performed.")


if __name__ == "__main__":
    main()
