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

"""Pure standard-library packaging tests; all macOS tools and Git operations are mocked.

Fixtures are retained in unique project build/release directories for inspection. No
real disk image, mount, application launch, signing or external Git write occurs.
"""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

PROJECT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("rest_release_packaging", PROJECT / "scripts/prepare-release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class PackagingTests(unittest.TestCase):
    def setUp(self):
        fixture_parent = PROJECT / "build/release"
        fixture_parent.mkdir(parents=True, exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix=".packaging-test-", dir=fixture_parent))
        self.assertTrue(self.root.resolve().is_relative_to(fixture_parent.resolve()))
        self.version = "1.2.3"
        self.tree = "f" * 40
        self.plist = {
            "CFBundleIdentifier": "local.restreminder.packaging-test",
            "CFBundleVersion": "7", "CFBundleExecutable": "RestReminder",
            "CFBundleShortVersionString": self.version,
            "LSMinimumSystemVersionByArchitecture": {"arm64": "12.0", "x86_64": "13.0"},
        }
        self.files = {
            "VERSION": (self.version + "\n").encode(),
            "Info.plist": plistlib.dumps(self.plist),
            "LICENSE": b"Synthetic CPAL-1.0 fixture\n",
            "Resources/PHOTO-CREDITS.md": b"Synthetic photograph credits\n",
            "build.sh": b"#!/bin/bash\n",
            "README.md": b"Synthetic source build instructions\n",
        }
        for name, content in self.files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        self.app = self.root / "isolated/歇一会儿.app"
        resources = self.app / "Contents/Resources"
        resources.mkdir(parents=True)
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps(self.plist))
        (resources / "SOURCE-CODE.txt").write_text("original app notice", encoding="utf-8")
        self.calls = []
        self.image_roots = []
        # Current hdiutil reports UDZO/Compressed but no writable property.
        self.image_information = {"Format": "UDZO", "Properties": {"Compressed": True}}
        self.fail_verify = False
        for patcher in (
            mock.patch.object(release, "ROOT", self.root),
            mock.patch.object(release, "git", side_effect=self.fake_git),
            mock.patch.object(release, "run", side_effect=self.fake_run),
            mock.patch.object(release, "run_process", side_effect=self.fake_process),
            mock.patch.object(release, "require_tools"),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    @property
    def output(self):
        return self.root / "build/release" / f"v{self.version}"

    def fake_git(self, *arguments):
        if arguments == ("rev-parse", "--show-toplevel"):
            return str(self.root).encode() + b"\n"
        if arguments == ("ls-files", "--stage", "-z"):
            return b"".join(b"100644 " + b"a" * 40 + b" 0\t" + name.encode() + b"\0" for name in self.files)
        if arguments == ("ls-files", "--others", "--exclude-standard", "-z"):
            return b""
        if arguments == ("write-tree",):
            return self.tree.encode() + b"\n"
        if arguments[0] == "show":
            return self.files[arguments[1].split(":", 1)[1]]
        if arguments[0] == "archive":
            prefix = next(value.removeprefix("--prefix=") for value in arguments if value.startswith("--prefix="))
            destination = Path(next(value.removeprefix("--output=") for value in arguments if value.startswith("--output=")))
            with zipfile.ZipFile(destination, "w") as archive:
                for name, content in self.files.items():
                    archive.writestr(prefix + name, content)
            return b""
        self.fail(f"Unexpected Git call: {arguments}")

    def fake_process(self, arguments, **kwargs):
        if arguments[:3] == ["git", "diff", "--quiet"]:
            return subprocess.CompletedProcess(arguments, 0, b"", b"")
        if arguments[:2] == ["/usr/bin/codesign", "--display"]:
            return subprocess.CompletedProcess(arguments, 0, b"", b"Signature=adhoc\n")
        self.fail(f"Unexpected process: {arguments}")

    def fake_run(self, arguments, *, timeout=120):
        self.calls.append((arguments, timeout))
        if arguments[0] == "/usr/bin/ditto":
            source, destination = map(Path, arguments[-2:])
            if "-c" in arguments:
                with zipfile.ZipFile(destination, "w") as archive:
                    for path in sorted(source.rglob("*")):
                        if path.is_file():
                            archive.write(path, str(Path(source.name) / path.relative_to(source)))
            else:
                shutil.copytree(source, destination, symlinks=True)
            return b""
        if arguments[0] == "/usr/bin/codesign":
            return b""
        if arguments[:2] == ["/usr/bin/hdiutil", "create"]:
            self.image_roots.append(Path(arguments[arguments.index("-srcfolder") + 1]))
            Path(arguments[-1]).write_bytes(b"synthetic compressed image; no real disk image created")
            return b""
        if arguments[:2] == ["/usr/bin/hdiutil", "verify"]:
            if self.fail_verify:
                raise release.ReleaseError("hdiutil failed (exit 1)")
            return b"verified fixture"
        if arguments[:2] == ["/usr/bin/hdiutil", "imageinfo"]:
            return plistlib.dumps(self.image_information)
        self.fail(f"Unexpected tool call: {arguments}")

    def prepare(self, **kwargs):
        with contextlib.redirect_stdout(io.StringIO()):
            release.prepare(self.app, **kwargs)

    def test_default_only_writes_the_original_two_zips(self):
        self.prepare()
        release.require_tools.assert_called_once_with(dmg=False)
        self.assertFalse(self.image_roots)
        self.assertFalse(any(args[0] == "/usr/bin/hdiutil" for args, _ in self.calls))
        manifest = json.loads((self.output / "release-manifest.json").read_text())
        names = {f"RestReminder-{self.version}-source.zip", f"RestReminder-{self.version}-macos-universal-ad-hoc.zip"}
        self.assertEqual(set(manifest["artifacts"]), names)
        self.assertNotIn("disk_image", manifest)
        with zipfile.ZipFile(self.output / f"RestReminder-{self.version}-macos-universal-ad-hoc.zip") as archive:
            self.assertFalse(any(Path(name).name == "Applications" for name in archive.namelist()))
            text = archive.read(f"RestReminder-{self.version}/RELEASE-INSTRUCTIONS.txt").decode()
            self.assertTrue(text.startswith(f"RestReminder {self.version}\n\nThis is a local ad-hoc signed build"))
        self.assertEqual(len((self.output / "SHA256SUMS").read_text().splitlines()), 3)
        self.assertEqual((self.app / "Contents/Resources/SOURCE-CODE.txt").read_text(), "original app notice")

    def test_dmg_has_its_own_root_link_instructions_source_and_checksums(self):
        self.prepare(dmg=True)
        release.require_tools.assert_called_once_with(dmg=True)
        self.assertEqual(len(self.image_roots), 1)
        root = self.image_roots[0]
        self.assertTrue(root.resolve().is_relative_to((self.root / "build/release").resolve()))
        self.assertEqual((root / "Applications").readlink(), Path("/Applications"))
        expected = {self.app.name, "Applications", f"RestReminder-{self.version}-source.zip", "LICENSE",
                    "PHOTO-CREDITS.md", "SOURCE-CODE.txt", "RELEASE-INSTRUCTIONS.txt"}
        self.assertEqual({entry.name for entry in root.iterdir()}, expected)
        for relative in ["SOURCE-CODE.txt", f"{self.app.name}/Contents/Resources/SOURCE-CODE.txt"]:
            notice = (root / relative).read_text()
            self.assertIn(self.tree, notice)
            self.assertIn(self.version, notice)
            self.assertIn(f"RestReminder-{self.version}-source.zip", notice)
        self.assertEqual((root / "LICENSE").read_bytes(), self.files["LICENSE"])
        instructions = (root / "RELEASE-INSTRUCTIONS.txt").read_text()
        for required in ["退出", "拖到", "Applications", "首次", "隐私与安全性", "ad-hoc", "公证", self.tree, self.version, "CPAL-1.0"]:
            self.assertIn(required, instructions)
        for unsafe_command in ["spctl --master-disable", "spctl --global-disable", "xattr -cr", "sudo"]:
            self.assertNotIn(unsafe_command, instructions)
        source_name = f"RestReminder-{self.version}-source.zip"
        self.assertEqual(release.digest(root / source_name), release.digest(self.output / source_name))
        binary_name = f"RestReminder-{self.version}-macos-universal-ad-hoc.zip"
        with zipfile.ZipFile(self.output / binary_name) as archive:
            self.assertFalse(any(Path(name).name == "Applications" for name in archive.namelist()))
            self.assertIn(b"This is a local ad-hoc signed build", archive.read(f"RestReminder-{self.version}/RELEASE-INSTRUCTIONS.txt"))
        image_name = f"RestReminder-{self.version}-macos-universal.dmg"
        manifest = json.loads((self.output / "release-manifest.json").read_text())
        self.assertEqual(manifest["source_git_tree"], self.tree)
        self.assertEqual(manifest["disk_image"], {"format": "UDZO", "compressed": True, "read_only": True, "verified": True})
        self.assertEqual(set(manifest["artifacts"]), {source_name, binary_name, image_name})
        for name, details in manifest["artifacts"].items():
            self.assertEqual(details["sha256"], release.digest(self.output / name))
            self.assertEqual(details["bytes"], (self.output / name).stat().st_size)
        sums = (self.output / "SHA256SUMS").read_text().splitlines()
        self.assertEqual(len(sums), 4)
        for line in sums:
            expected_digest, name = line.split("  ", 1)
            self.assertEqual(expected_digest, release.digest(self.output / name))
        tool_calls = [(args, timeout) for args, timeout in self.calls if args[0] == "/usr/bin/hdiutil"]
        self.assertEqual([args[1] for args, _ in tool_calls], ["create", "verify", "imageinfo"])
        create, timeout = tool_calls[0]
        self.assertEqual(create[create.index("-format") + 1], "UDZO")
        self.assertEqual(create[create.index("-fs") + 1], "HFS+")
        self.assertNotIn("-ov", create)
        self.assertEqual(timeout, 600)
        self.assertEqual(tool_calls[1][1], 300)
        self.assertTrue(all(0 < timeout <= 600 for _, timeout in tool_calls))

    def test_failed_verification_retains_staging_and_does_not_publish_manifest(self):
        self.fail_verify = True
        with self.assertRaises(release.ReleaseError):
            self.prepare(dmg=True)
        self.assertTrue(self.image_roots[0].is_dir())
        self.assertFalse((self.output / "release-manifest.json").exists())
        self.assertFalse((self.output / "SHA256SUMS").exists())
        with self.assertRaisesRegex(release.ReleaseError, "already exists"):
            self.prepare(dmg=True)

    def test_wrong_disk_image_format_is_rejected(self):
        self.image_information = {"Format": "UDRW", "Properties": {"Compressed": False, "Writeable": True}}
        with self.assertRaisesRegex(release.ReleaseError, "compressed read-only UDZO"):
            self.prepare(dmg=True)
        self.assertFalse((self.output / "release-manifest.json").exists())

    def test_missing_dmg_tool_fails_before_creating_release_output(self):
        release.require_tools.side_effect = release.ReleaseError("Required macOS tool is unavailable: hdiutil")
        with self.assertRaisesRegex(release.ReleaseError, "hdiutil"):
            self.prepare(dmg=True)
        self.assertFalse(self.output.exists())
        self.assertEqual(self.calls, [])

    def test_read_only_and_compression_properties_are_required(self):
        distribution = self.root / "synthetic-distribution"
        distribution.mkdir()
        invalid = [
            {"Format": "UDZO", "Properties": {"Compressed": False, "Writeable": False}},
            {"Format": "UDZO", "Properties": {"Compressed": True, "Writeable": True}},
            {"Format": "UDZO", "Properties": {"Compressed": True, "Writable": True}},
            {"Format": "UDZO", "Properties": {"Compressed": True}, "Writable": True},
            {"Format": "UDZO", "Properties": {}},
            [],
        ]
        for index, information in enumerate(invalid):
            with self.subTest(information=information):
                staging = self.root / "build/release" / f"invalid-image-{index}"
                staging.mkdir(parents=True)
                self.image_information = information
                with self.assertRaises(release.ReleaseError):
                    release.create_dmg(distribution, staging, staging / "test.dmg",
                                       self.version, self.tree, "source.zip", self.app.name)

    def test_existing_version_output_is_never_overwritten(self):
        self.output.mkdir(parents=True)
        sentinel = self.output / "keep.txt"
        sentinel.write_text("keep existing release")
        with self.assertRaisesRegex(release.ReleaseError, "already exists"):
            self.prepare(dmg=True)
        self.assertEqual(sentinel.read_text(), "keep existing release")
        self.assertEqual(self.calls, [])

    def test_dangling_output_symlink_is_treated_as_occupied(self):
        self.output.parent.mkdir(parents=True)
        target = self.root / "not-created"
        self.output.symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(release.ReleaseError, "already exists"):
            self.prepare(dmg=True)
        self.assertEqual(self.output.readlink(), target)
        self.assertFalse(target.exists())
        self.assertEqual(self.calls, [])


class InterfacesAndSafetyTests(unittest.TestCase):
    def test_dmg_flag_is_explicit_and_optional(self):
        for enabled in [False, True]:
            arguments = ["prepare-release.py", "--app", "isolated.app"] + (["--dmg"] if enabled else [])
            with self.subTest(dmg=enabled), mock.patch.object(sys, "argv", arguments), mock.patch.object(release, "prepare") as prepare:
                release.main()
                prepare.assert_called_once_with(Path("isolated.app"), dmg=enabled)

    def test_hdiutil_is_required_only_when_requested(self):
        def available(path):
            return path.name != "hdiutil"
        with mock.patch.object(Path, "is_file", available):
            release.require_tools()
            with self.assertRaisesRegex(release.ReleaseError, "hdiutil"):
                release.require_tools(dmg=True)

    def test_subprocesses_are_bounded_and_errors_do_not_leak_output(self):
        completed = subprocess.CompletedProcess(["git"], 0, b"result", b"")
        with mock.patch.object(release.subprocess, "run", return_value=completed) as process:
            self.assertEqual(release.run(["git", "status"]), b"result")
            self.assertEqual(process.call_args.kwargs["timeout"], 120)
        timeout = subprocess.TimeoutExpired(["/usr/bin/hdiutil"], 600, output=b"private output", stderr=b"private error")
        with mock.patch.object(release.subprocess, "run", side_effect=timeout):
            with self.assertRaisesRegex(release.ReleaseError, "hdiutil timed out after 600") as failure:
                release.run(["/usr/bin/hdiutil", "create"], timeout=600)
            self.assertNotIn("private", str(failure.exception))
        failed = subprocess.CompletedProcess(["git"], 3, b"private output", b"private error")
        with mock.patch.object(release.subprocess, "run", return_value=failed):
            with self.assertRaisesRegex(release.ReleaseError, "git failed") as failure:
                release.run(["git", "show"])
            self.assertNotIn("private", str(failure.exception))


if __name__ == "__main__":
    unittest.main()
