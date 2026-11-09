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

"""Check public docs without build outputs; optionally compare previews or make a ZIP."""

import argparse
import hashlib
from html.parser import HTMLParser
from pathlib import Path
import re
import struct
import unicodedata
from urllib.parse import unquote, urlsplit
import zipfile

ROOT = Path(__file__).resolve().parent.parent
PREVIEWS = {
    "welcome.png": "build/welcome-preview.png",
    "exercise.png": "build/exercise-preview.png",
    "strong-rest.png": "build/strong-rest-preview.png",
    "history.png": "build/history-preview.png",
    "status-ring.png": "build/status-ring-preview.png",
    "history-week.png": "build/history-week-preview.png",
    "app-icon.png": "Resources/AppIcon.png",
    "voluntary-rest.png": "build/voluntary-rest-preview.png",
    "history-merged.png": "build/history-merged-preview.png",
    "about-settings.png": "build/about-settings-preview.png",
}
PRIVATE = re.compile(r"/Users/|/home/|127\.0\.0\.1|\.dsh/|BEGIN [A-Z ]*PRIVATE KEY", re.I)


class HTMLLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if values.get("id"):
            self.ids.add(values["id"])
        if tag == "img" and values.get("src"):
            self.links.append((self.getpos()[0], values["src"]))
        if tag == "a" and values.get("name"):
            self.ids.add(values["name"])


def prose(text, name, errors):
    """Preserve line numbers while removing fenced examples from link/heading checks."""
    result, fence = [], None
    for number, line in enumerate(text.splitlines(), 1):
        match = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line)
        if match and fence is None:
            fence = (match[1][0], len(match[1]), number)
            result.append("")
        elif match and fence and match[1][0] == fence[0] and len(match[1]) >= fence[1] and not match[2].strip():
            fence = None
            result.append("")
        else:
            result.append("" if fence else line)
    if fence:
        errors.append(f"{name}:{fence[2]}: unbalanced code fence")
    return "\n".join(result)


def anchors(text):
    result, seen = set(), {}
    for line in text.splitlines():
        match = re.match(r"^ {0,3}#{1,6}\s+(.+?)(?:\s+#+\s*)?$", line)
        if not match:
            continue
        heading = re.sub(r"!?\[([^\]]+)\]\([^)]*\)", r"\1", match[1]).lower()
        slug = "".join(c for c in heading if c in "-_ " or unicodedata.category(c)[0] in "LNM").replace(" ", "-")
        count = seen.get(slug, 0)
        seen[slug] = count + 1
        result.add(slug if count == 0 else f"{slug}-{count}")
    parser = HTMLLinks()
    parser.feed(text)
    return result | parser.ids


def targets(text):
    # Angle brackets support spaces; an optional quoted Markdown title is not a path.
    pattern = r"!?\[[^\]]*\]\(\s*(<[^>]+>|[^\s)]+)(?:\s+\"[^\"]*\"|\s+'[^']*')?\s*\)"
    for match in re.finditer(pattern, text):
        yield text.count("\n", 0, match.start()) + 1, match[1].strip("<>")
    for match in re.finditer(r"^ {0,3}\[[^\]]+\]:\s*(<[^>]+>|\S+)", text, re.M):
        yield text.count("\n", 0, match.start()) + 1, match[1].strip("<>")
    parser = HTMLLinks()
    parser.feed(text)
    yield from parser.links


def png_size(path):
    with path.open("rb") as image:
        header = image.read(33)
    if len(header) != 33 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[8:16] != b"\x00\x00\x00\rIHDR":
        raise ValueError("invalid PNG header")
    width, height = struct.unpack(">II", header[16:24])
    if not width or not height or width > 0x7FFFFFFF or height > 0x7FFFFFFF:
        raise ValueError("invalid PNG dimensions")
    return width, height


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compare-build-previews", action="store_true", help="Require exact hashes against the ten original preview inputs, including build PNGs")
    parser.add_argument("--package", action="store_true", help="After validation, create build/RestReminder-docs.zip")
    args = parser.parse_args()
    errors, count = [], 0
    files = sorted(set(ROOT.glob("*.md")) | set((ROOT / "docs").rglob("*.md")) | {ROOT / "Resources/PHOTO-CREDITS.md"})
    documents = {}
    for path in files:
        name = path.relative_to(ROOT).as_posix()
        if not path.resolve().is_relative_to(ROOT):
            errors.append(f"{name}: document escapes project root")
            continue
        text = path.read_text(encoding="utf-8")
        for number, line in enumerate(text.splitlines(), 1):
            if PRIVATE.search(line):
                errors.append(f"{name}:{number}: private workspace or key marker (value withheld)")
        documents[path] = prose(text, name, errors)
    for path, text in documents.items():
        name = path.relative_to(ROOT).as_posix()
        for line, target in targets(text):
            try:
                parts = urlsplit(target)
                if parts.scheme or parts.netloc:
                    continue
                count += 1
                local = (path.parent / unquote(parts.path)).resolve() if parts.path else path
                if not local.is_relative_to(ROOT):
                    errors.append(f"{name}:{line}: local link escapes project root")
                elif not local.exists():
                    errors.append(f"{name}:{line}: missing local link")
                elif parts.fragment and local.suffix.lower() == ".md":
                    target_text = documents.get(local)
                    if target_text is None:
                        target_text = prose(local.read_text(encoding="utf-8"), local.relative_to(ROOT).as_posix(), errors)
                    if unquote(parts.fragment) not in anchors(target_text):
                        errors.append(f"{name}:{line}: missing local anchor")
            except (OSError, ValueError) as error:
                errors.append(f"{name}:{line}: invalid local link ({type(error).__name__})")
    requirements = documents.get(ROOT / "docs/requirements.md", "")
    for number in range(1, 32):
        if not re.search(rf"\bFR-{number:02d}\b", requirements):
            errors.append(f"docs/requirements.md: missing FR-{number:02d}")
    for name, original in PREVIEWS.items():
        public = ROOT / "docs/assets" / name
        try:
            png_size(public)
            if args.compare_build_previews and hashlib.sha256((ROOT / original).read_bytes()).digest() != hashlib.sha256(public.read_bytes()).digest():
                errors.append(f"docs/assets/{name}: preview hash differs")
        except (OSError, ValueError):
            errors.append(f"docs/assets/{name}: missing/invalid PNG or comparison input")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"PASS: {len(documents)} Markdown files, {count} local links/anchors, balanced fences, privacy markers, FR-01..31, {len(PREVIEWS)} PNG dimensions")
    if args.compare_build_previews:
        print(f"PASS: {len(PREVIEWS)} exact preview hashes")
    if args.package:
        names = ["README.md", "LICENSE", "CHANGELOG.md", "VERSION", "docs/requirements.md", "docs/design.md"]
        names += [f"docs/assets/{name}" for name in PREVIEWS]
        if (ROOT / "RELEASING.md").exists():
            names.append("RELEASING.md")
        if any(not (ROOT / name).is_file() for name in names):
            raise SystemExit("Documentation package input missing; require README, LICENSE, CHANGELOG, VERSION and both design documents")
        destination = ROOT / "build/RestReminder-docs.zip"
        if not destination.resolve().is_relative_to(ROOT / "build"):
            raise SystemExit("Documentation output escapes build directory")
        destination.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
            for name in names:
                archive.write(ROOT / name, name)
        with zipfile.ZipFile(destination) as archive:
            if set(archive.namelist()) != set(names) or archive.testzip() is not None:
                raise SystemExit("Documentation archive verification failed")
        print(f"PASS: {len(names)} files in {destination.relative_to(ROOT).as_posix()}")


if __name__ == "__main__":
    main()
