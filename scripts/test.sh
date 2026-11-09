#!/bin/bash
# SPDX-License-Identifier: CPAL-1.0
#
# EXHIBIT A. Common Public Attribution License Version 1.0.
#
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
#
# [NOTE: The text of this Exhibit A may differ slightly from the text of the notices in the Source Code files of the Original Code. You should use the text of this Exhibit A rather than the text found in the Original Code Source Code for Your Modifications.]
#
# For Exhibit B Attribution Information, see the root LICENSE file.

# Deterministic, native tests only. Usage: ./scripts/test.sh [timing audio locks escalation history protection ring advice instance voluntary]
# Does not launch the app, audio capture, metadata smoke, login registration, or fullscreen UI.
# SWIFTC/SDKROOT/DEVELOPER_DIR follow build.sh; TEST_DEPLOYMENT_TARGET can require a minimum.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
if [[ "$#" -eq 0 ]]; then set -- timing audio locks escalation history protection ring advice instance voluntary; fi
for suite in "$@"; do
    case "$suite" in
        timing|audio|locks|escalation|history|protection|ring|advice|instance|voluntary) ;;
        *) fail "Unknown deterministic suite: $suite" ;;
    esac
done
SWIFTC="${SWIFTC:-$("$PROJECT_DIR/build.sh" --print-swiftc)}"
SDK="$("$PROJECT_DIR/build.sh" --print-sdk)"
ARCH="$(/usr/bin/uname -m)"
[[ "$ARCH" == arm64 || "$ARCH" == x86_64 ]] || fail "Unsupported native test architecture: $ARCH"
BUILD_ROOT="${BUILD_DIR:-$PROJECT_DIR/build}"
mkdir -p "$BUILD_ROOT"
BUILD_ROOT="$(cd "$BUILD_ROOT" && pwd -P)"
WORK="$(mktemp -d "$BUILD_ROOT/tests.XXXXXX")"
mkdir -p "$WORK/build" "$WORK/module-cache"
# Existing history/ring tests write relative build fixtures; isolate their cwd from app artifacts.
cd "$WORK"
printf 'Test workspace: %s\nNative test architecture: %s\nCompiler: %s\nSDK: %s\n' "$WORK" "$ARCH" "$SWIFTC" "$SDK"
printf '%s\n' 'import Foundation' 'print("native test link probe")' > "$WORK/probe.swift"
if [[ -n "${TEST_DEPLOYMENT_TARGET:-}" ]]; then candidates=("$TEST_DEPLOYMENT_TARGET"); else candidates=(12.0 13.0); fi
TARGET=""
for candidate in "${candidates[@]}"; do
    [[ "$candidate" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail 'TEST_DEPLOYMENT_TARGET must be a version such as 12.0.'
    if "$SWIFTC" -sdk "$SDK" -target "$ARCH-apple-macosx$candidate" -module-cache-path "$WORK/module-cache" \
        "$WORK/probe.swift" -o "$WORK/probe" >"$WORK/probe-$candidate.log" 2>&1; then
        TARGET="$candidate"; break
    fi
    printf 'Native test minimum %s cannot link; see %s\n' "$candidate" "$WORK/probe-$candidate.log" >&2
    /usr/bin/tail -n 12 "$WORK/probe-$candidate.log" >&2
done
[[ -n "$TARGET" ]] || fail 'No linkable native test target. Select a complete Swift toolchain.'
for suite in "$@"; do
    frameworks=()
    case "$suite" in
        timing) sources=(Sources/ActivitySession.swift Tests/main.swift) ;;
        audio) sources=(Sources/RestContinuousClock.swift Sources/ActivitySession.swift Sources/AudioPlaybackMonitor.swift Tests/AudioTests.swift); frameworks=(-framework CoreAudio) ;;
        locks) sources=(Sources/ActivitySession.swift Tests/LockReturnTests.swift) ;;
        escalation) sources=(Sources/ActivitySession.swift Sources/RestEscalation.swift Tests/EscalationTests.swift) ;;
        history) sources=(Sources/ActivityHistory.swift Tests/HistoryTests.swift) ;;
        protection) sources=(Sources/RestContinuousClock.swift Sources/PresentationProtection.swift Tests/PresentationProtectionTests.swift); frameworks=(-framework AppKit -framework AVFoundation -framework CoreGraphics) ;;
        ring) sources=(Sources/StatusProgressRing.swift Tests/StatusRingTests.swift); frameworks=(-framework AppKit) ;;
        advice) sources=(Sources/RestAdvice.swift Tests/RestAdviceTests.swift) ;;
        instance) sources=(Sources/SingleInstanceGuard.swift Tests/SingleInstanceTests.swift) ;;
        voluntary) sources=(Sources/VoluntaryRest.swift Sources/ActivityHistory.swift Tests/VoluntaryRestTests.swift) ;;
        *) fail "Unknown deterministic suite: $suite" ;;
    esac
    for index in "${!sources[@]}"; do
        sources[$index]="$PROJECT_DIR/${sources[$index]}"
        [[ -f "${sources[$index]}" ]] || fail "Missing suite source: ${sources[$index]}"
    done
    printf '\nRunning %s (native %s, macOS %s minimum)\n' "$suite" "$ARCH" "$TARGET"
    # The + expansion permits an empty frameworks array under Apple's Bash 3.2 + nounset.
    "$SWIFTC" -sdk "$SDK" -target "$ARCH-apple-macosx$TARGET" -module-cache-path "$WORK/module-cache" \
        "${sources[@]}" ${frameworks[@]+"${frameworks[@]}"} -o "$WORK/$suite-tests"
    "$WORK/$suite-tests"
done
printf '\nAll requested deterministic suites passed. Fixtures: %s\n' "$WORK/build"
