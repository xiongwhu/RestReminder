#!/bin/bash
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

# Build without launching: ./build.sh
# ARCHS=arm64|x86_64|native|universal (default: both when SDK advertises both).
# MACOSX_DEPLOYMENT_TARGET=12.0 requires that exact target; otherwise try 12 then 13 per arch.
# SDKROOT/SWIFTC/DEVELOPER_DIR override discovery. BUILD_DIR isolates concurrent build output.
# --typecheck-only checks source availability; --verify-only [app] verifies an existing bundle.
# --print-swiftc / --print-sdk are read-only toolchain queries used by scripts/test.sh.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

choose_toolchain() {
    local developer="${DEVELOPER_DIR:-}" candidate
    if [[ -z "$developer" && -d /Library/Developer/CommandLineTools ]]; then
        developer=/Library/Developer/CommandLineTools
    fi
    if [[ -z "${SWIFTC:-}" ]]; then
        for candidate in "$developer/usr/bin/swiftc" "$developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"; do
            if [[ -n "$developer" && -x "$candidate" ]]; then SWIFTC="$candidate"; break; fi
        done
        # On standard CI hosts xcrun can select the installed, licensed developer tools.
        if [[ -z "${SWIFTC:-}" && -z "${DEVELOPER_DIR:-}" ]]; then
            SWIFTC="$(/usr/bin/xcrun --find swiftc)" || fail 'Select a working developer directory or set SWIFTC.'
        fi
    fi
    [[ -n "${SWIFTC:-}" && -x "$SWIFTC" ]] || fail 'SWIFTC/DEVELOPER_DIR does not contain a Swift compiler.'
    SWIFTC="$(cd "$(dirname "$SWIFTC")" && pwd -P)/$(basename "$SWIFTC")"
    SDK="${SDKROOT:-}"
    if [[ -z "$SDK" ]]; then
        for candidate in "$developer/SDKs/MacOSX.sdk" "$developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"; do
            if [[ -n "$developer" && -d "$candidate" ]]; then SDK="$candidate"; break; fi
        done
        if [[ -z "$SDK" ]]; then
            SDK="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)" || fail 'Set SDKROOT to an installed macOS SDK.'
        fi
    fi
    [[ -d "$SDK" && -f "$SDK/SDKSettings.json" ]] || fail "SDKROOT is not a macOS SDK directory: $SDK"
    SDK="$(cd "$SDK" && pwd -P)"
    LIPO="$(dirname "$SWIFTC")/lipo"
    OTOOL="$(dirname "$SWIFTC")/otool"
    [[ -x "$LIPO" ]] || LIPO=/usr/bin/lipo
    [[ -x "$OTOOL" ]] || OTOOL=/usr/bin/otool
    [[ -x "$LIPO" && -x "$OTOOL" ]] || fail 'Missing lipo or otool in the selected toolchain.'
}

same_version() {
    /usr/bin/awk -v left="$1" -v right="$2" 'BEGIN {
        split(left,a,"."); split(right,b,".");
        for (i=1;i<=3;i++) if ((a[i]+0)!=(b[i]+0)) exit 1;
    }'
}

binary_minimum() {
    "$OTOOL" -arch "$1" -l "$2" | /usr/bin/awk '
        $1 == "cmd" { command=$2 }
        command == "LC_BUILD_VERSION" && $1 == "minos" && !found { print $2; found=1 }
        command == "LC_VERSION_MIN_MACOSX" && $1 == "version" && !found { print $2; found=1 }
        END { if (!found) exit 1 }'
}

verify_bundle() {
    local app="$1" binary="$1/Contents/MacOS/RestReminder" plist="$1/Contents/Info.plist"
    [[ -f "$binary" && -f "$plist" ]] || fail "Incomplete bundle: $app"
    /usr/bin/plutil -lint "$plist" >/dev/null
    local arches arch minimum declared overall expected lowest=""
    arches="$("$LIPO" -archs "$binary")"
    [[ -n "$arches" ]] || fail 'Executable contains no architectures.'
    overall="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")"
    for arch in $arches; do
        [[ "$arch" == arm64 || "$arch" == x86_64 ]] || fail "Unexpected architecture: $arch"
        minimum="$(binary_minimum "$arch" "$binary")" || fail "Missing deployment metadata for $arch"
        declared="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersionByArchitecture:$arch" "$plist")" || fail "Missing minimum for $arch"
        same_version "$minimum" "$declared" || fail "$arch binary minimum $minimum differs from plist $declared"
        if [[ -z "$lowest" ]] || /usr/bin/awk -v a="$minimum" -v b="$lowest" 'BEGIN {exit !(a+0 < b+0)}'; then lowest="$minimum"; fi
        printf 'Verified %s: macOS %s minimum\n' "$arch" "$minimum"
    done
    same_version "$overall" "$lowest" || fail "Global plist minimum $overall differs from the lowest slice $lowest"
    if [[ -n "${SELECTED_ARCHES[0]:-}" ]]; then
        for expected in "${SELECTED_ARCHES[@]}"; do
            case " $arches " in *" $expected "*) ;; *) fail "Missing requested architecture: $expected" ;; esac
        done
        local actual_list=($arches)
        [[ "${#actual_list[@]}" == "${#SELECTED_ARCHES[@]}" ]] || fail 'Unexpected executable architecture count.'
    fi
    /usr/bin/codesign --verify --all-architectures --deep --strict --verbose=2 "$app"
    local signature
    signature="$(/usr/bin/codesign --display --verbose=4 "$app" 2>&1)"
    case "$signature" in *'Signature=adhoc'*) ;; *) fail 'Expected the local ad-hoc signature.' ;; esac
    printf 'Verified architectures: %s; ad-hoc signature valid\n' "$arches"
}

choose_toolchain
case "${1:-}" in
    --print-swiftc) printf '%s\n' "$SWIFTC"; exit 0 ;;
    --print-sdk) printf '%s\n' "$SDK"; exit 0 ;;
    --help|-h) /usr/bin/sed -n '2,7p' "$0"; exit 0 ;;
    --verify-only) SELECTED_ARCHES=(); verify_bundle "${2:-$PROJECT_DIR/build/歇一会儿.app}"; exit 0 ;;
    ''|--typecheck-only) ;;
    *) fail "Unknown option: $1" ;;
esac

SDK_ARCHES="$(/usr/bin/plutil -extract SupportedTargets.macosx.Archs json -o - "$SDK/SDKSettings.json")"
case "${ARCHS:-auto}" in
    auto)
        if [[ "$SDK_ARCHES" == *'"arm64"'* && "$SDK_ARCHES" == *'"x86_64"'* ]]; then
            SELECTED_ARCHES=(arm64 x86_64)
        else SELECTED_ARCHES=("$(/usr/bin/uname -m)"); fi ;;
    universal) SELECTED_ARCHES=(arm64 x86_64) ;;
    native) SELECTED_ARCHES=("$(/usr/bin/uname -m)") ;;
    arm64|x86_64) SELECTED_ARCHES=("$ARCHS") ;;
    'arm64 x86_64'|'x86_64 arm64') SELECTED_ARCHES=(arm64 x86_64) ;;
    *) fail 'ARCHS must be arm64, x86_64, native, or universal.' ;;
esac
for arch in "${SELECTED_ARCHES[@]}"; do
    [[ "$SDK_ARCHES" == *\""$arch"\"* ]] || fail "Selected SDK does not advertise $arch: $SDK"
done

SOURCES=(PresentationProtection.swift StatusProgressRing.swift RestEscalation.swift
    StrongRestWindow.swift ActivityHistory.swift HistoryWindow.swift AudioPlaybackMonitor.swift
    ActivitySession.swift ReturnCelebration.swift main.swift SingleInstanceGuard.swift
    RestContinuousClock.swift RestAdvice.swift VoluntaryRest.swift AboutBrandView.swift)
for index in "${!SOURCES[@]}"; do
    SOURCES[$index]="$PROJECT_DIR/Sources/${SOURCES[$index]}"
    [[ -f "${SOURCES[$index]}" ]] || fail "Missing app source: ${SOURCES[$index]}"
done
FRAMEWORKS=(-framework AppKit -framework AVFoundation -framework CoreGraphics -framework CoreAudio -framework ServiceManagement)
BUILD_ROOT="${BUILD_DIR:-$PROJECT_DIR/build}"
mkdir -p "$BUILD_ROOT"
BUILD_ROOT="$(cd "$BUILD_ROOT" && pwd -P)"
WORK="$(mktemp -d "$BUILD_ROOT/compile.XXXXXX")"
# An explicit cache root may reuse SDK imports between checks; objects and binaries stay unique.
CACHE_ROOT="${MODULE_CACHE_DIR:-$WORK}"
APP="$BUILD_ROOT/歇一会儿.app"
printf 'Compiler: %s\nSDK: %s\nBuild workspace: %s\n' "$SWIFTC" "$SDK" "$WORK"
printf '%s\n' 'import AppKit' 'import AVFoundation' 'import CoreAudio' 'import ServiceManagement' 'print("link probe")' > "$WORK/probe.swift"

REQUESTED_TARGET="${MACOSX_DEPLOYMENT_TARGET:-}"
if [[ -n "$REQUESTED_TARGET" ]]; then
    [[ "$REQUESTED_TARGET" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail 'MACOSX_DEPLOYMENT_TARGET must be a version such as 12.0.'
    (( ${REQUESTED_TARGET%%.*} >= 12 )) || fail 'Targets below macOS 12 are not supported.'
fi
MINIMA=()
for arch in "${SELECTED_ARCHES[@]}"; do
    mkdir -p "$WORK/$arch" "$CACHE_ROOT/cache-$arch"
    if [[ -n "$REQUESTED_TARGET" ]]; then candidates=("$REQUESTED_TARGET"); else candidates=(12.0 13.0); fi
    chosen=""
    for minimum in "${candidates[@]}"; do
        log="$WORK/$arch/target-$minimum.log"
        # Availability errors and missing architecture runtime archives must both prevent selection.
        # Do not disable runtime compatibility libraries to force an older deployment claim.
        if "$SWIFTC" -sdk "$SDK" -target "$arch-apple-macosx$minimum" -module-cache-path "$CACHE_ROOT/cache-$arch" \
                "$WORK/probe.swift" "${FRAMEWORKS[@]}" -o "$WORK/$arch/probe" >"$log" 2>&1 &&
           "$SWIFTC" -sdk "$SDK" -target "$arch-apple-macosx$minimum" -module-cache-path "$CACHE_ROOT/cache-$arch" \
                -typecheck "${SOURCES[@]}" "${FRAMEWORKS[@]}" >>"$log" 2>&1; then
            chosen="$minimum"
            break
        fi
        printf 'Cannot use %s macOS %s; diagnostics: %s\n' "$arch" "$minimum" "$log" >&2
        /usr/bin/tail -n 16 "$log" >&2
    done
    [[ -n "$chosen" ]] || fail "No source-supported, linkable target for $arch. Inspect the logs above."
    MINIMA+=("$chosen")
    printf 'Selected %s deployment target: macOS %s\n' "$arch" "$chosen"
done
if [[ "${1:-}" == --typecheck-only ]]; then exit 0; fi

BINARIES=()
for index in "${!SELECTED_ARCHES[@]}"; do
    arch="${SELECTED_ARCHES[$index]}"
    minimum="${MINIMA[$index]}"
    "$SWIFTC" -sdk "$SDK" -target "$arch-apple-macosx$minimum" -module-cache-path "$CACHE_ROOT/cache-$arch" \
        -O -whole-module-optimization -emit-object "${SOURCES[@]}" -o "$WORK/$arch/RestReminder.o"
    "$SWIFTC" -sdk "$SDK" -target "$arch-apple-macosx$minimum" \
        "$WORK/$arch/RestReminder.o" "${FRAMEWORKS[@]}" -o "$WORK/$arch/RestReminder"
    actual="$(binary_minimum "$arch" "$WORK/$arch/RestReminder")"
    same_version "$actual" "$minimum" || fail "Linker produced $arch minimum $actual instead of $minimum"
    BINARIES+=("$WORK/$arch/RestReminder")
done
# Combine complete per-architecture binaries, never reuse objects between architectures.
"$LIPO" -create "${BINARIES[@]}" -output "$WORK/RestReminder"
# Some CLT lipo versions accept only one architecture per verify invocation.
for arch in "${SELECTED_ARCHES[@]}"; do "$LIPO" "$WORK/RestReminder" -verify_arch "$arch"; done

for resource in morning-sun-candidate.jpg fresh-green.jpg PHOTO-CREDITS.md; do
    [[ -f "$PROJECT_DIR/Resources/$resource" ]] || fail "Missing app resource: $resource"
done
if [[ -f "$PROJECT_DIR/Resources/AppIcon.png" && ! -f "$PROJECT_DIR/Resources/AppIcon.icns" ]]; then
    fail 'AppIcon.png exists but AppIcon.icns is missing; finish icon generation before bundling.'
fi
if [[ "${REQUIRE_APP_ICON:-0}" == 1 && ! -f "$PROJECT_DIR/Resources/AppIcon.icns" ]]; then
    fail 'Resources/AppIcon.icns is required for this build.'
fi
[[ -f "$PROJECT_DIR/LICENSE" ]] || fail 'Missing CPAL-1.0 LICENSE.'
/usr/bin/plutil -lint "$PROJECT_DIR/Info.plist" >/dev/null
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$WORK/RestReminder" "$APP/Contents/MacOS/RestReminder"
cp "$PROJECT_DIR/Info.plist" "$APP/Contents/Info.plist"
PLIST="$APP/Contents/Info.plist"
# Declare both the lowest compatible slice and each architecture's measured minimum.
lowest="${MINIMA[0]}"
for minimum in "${MINIMA[@]}"; do
    if /usr/bin/awk -v a="$minimum" -v b="$lowest" 'BEGIN {exit !(a+0 < b+0)}'; then lowest="$minimum"; fi
done
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $lowest" "$PLIST"
/usr/bin/plutil -replace LSMinimumSystemVersionByArchitecture -json '{}' "$PLIST"
for index in "${!SELECTED_ARCHES[@]}"; do
    /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersionByArchitecture:${SELECTED_ARCHES[$index]} string ${MINIMA[$index]}" "$PLIST"
done
cp "$PROJECT_DIR/Resources/morning-sun-candidate.jpg" "$APP/Contents/Resources/morning-sun.jpg"
cp "$PROJECT_DIR/Resources/fresh-green.jpg" "$APP/Contents/Resources/fresh-green.jpg"
cp "$PROJECT_DIR/Resources/PHOTO-CREDITS.md" "$APP/Contents/Resources/PHOTO-CREDITS.md"
cp "$PROJECT_DIR/LICENSE" "$APP/Contents/Resources/LICENSE"
cat > "$APP/Contents/Resources/SOURCE-CODE.txt" <<'SOURCE_NOTICE'
RestReminder (歇一会儿) — source availability

The Covered Code and its Modifications are available under CPAL-1.0.
Redistributors must provide the corresponding source and preserve the
applicable notices and attribution, as described in the bundled LICENSE.

The official release packaging tool includes the corresponding source ZIP
in the same distribution directory as this application and writes its exact
version and Git tree to this notice. If you received only this application,
request the matching source archive and source-availability notice from
its distributor before redistributing it.
SOURCE_NOTICE
if [[ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else printf 'warning: AppIcon.icns has not been generated; this development build has no icon.\n' >&2; fi
if [[ -f "$PROJECT_DIR/Resources/AppIcon.png" ]]; then cp "$PROJECT_DIR/Resources/AppIcon.png" "$APP/Contents/Resources/AppIcon.png"; fi
/usr/bin/codesign --force --sign - "$APP"
verify_bundle "$APP"
printf 'Built: %s\nLocal ad-hoc build; no Developer ID or notarization. Intel slice was cross-compiled, not tested on Intel hardware.\n' "$APP"
