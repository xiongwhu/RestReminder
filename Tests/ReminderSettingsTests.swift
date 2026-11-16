// SPDX-License-Identifier: CPAL-1.0
//
// EXHIBIT A. Common Public Attribution License Version 1.0.
//
// The contents of this file are subject to the Common Public Attribution License Version 1.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at https://opensource.org/license/cpal-1-0. The License is based on the Mozilla Public License Version 1.1 but Sections 14 and 15 have been added to cover use of software over a computer network and provide for limited attribution for the Original Developer. In addition, Exhibit A has been modified to be consistent with Exhibit B.
//
// Software distributed under the License is distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for the specific language governing rights and limitations under the License.
//
// The Original Code is RestReminder (歇一会儿), including the original source code, tests and build scripts distributed in this repository. Third-party photographs identified in Resources/PHOTO-CREDITS.md are excluded and remain subject to their original licenses.
// The Initial Developer of the Original Code is 广州迈润网络科技有限公司 (迈润智人 RaCIO).
// The Original Developer is the Initial Developer.
// All portions of the code written by the Initial Developer are Copyright (c) 2026 广州迈润网络科技有限公司. All Rights Reserved.
// Contributor(s): see individual source notices and project history.
// No alternative license is designated for the Original Code.
//
// [NOTE: The text of this Exhibit A may differ slightly from the text of the notices in the Source Code files of the Original Code. You should use the text of this Exhibit A rather than the text found in the Original Code Source Code for Your Modifications.]
//
// For Exhibit B Attribution Information, see the root LICENSE file.

import Foundation

@main
struct ReminderSettingsTests {
    enum Failure: Error { case assertion(String) }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure.assertion(message) }
    }

    static func main() throws {
        let suite = "local.restreminder.settings-tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Cannot create isolated preference suite") }
        defer { defaults.removePersistentDomain(forName: suite) }
        print("Isolated settings suite: \(suite)")
        typealias Duration = ReminderSettings.Duration
        for duration in Duration.allCases {
            try expect(defaults.object(forKey: duration.key) == nil, "Unique test suite starts empty")
            try expect(duration.minutes(in: defaults) == duration.defaultMinutes, "Missing preference falls back")
            try expect(defaults.object(forKey: duration.key) == nil, "Safe reads do not mutate preferences")
        }
        ReminderSettings.normalize(in: defaults)
        try expect(Duration.work.minutes(in: defaults) == 30 && Duration.rest.minutes(in: defaults) == 2,
               "Launch normalization installs the documented defaults")

        let wrongTypes: [Any] = ["30", "2.5", true, false, NSNumber(value: true), NSNumber(value: false),
                                 [1, 2], ["minutes": 30], Date(timeIntervalSince1970: 0), Data([1])]
        for duration in Duration.allCases {
            try expect(duration.validatedMinutes(nil) == nil && duration.validatedMinutes(NSNull()) == nil,
                   "Missing and null are not numbers")
            for object in wrongTypes {
                try expect(duration.validatedMinutes(object) == nil, "Reject wrong preference type: \(object)")
                defaults.set(object, forKey: duration.key)
                try expect(duration.minutes(in: defaults) == duration.defaultMinutes,
                       "Read path rejects externally changed preference type")
                ReminderSettings.normalize(in: defaults)
                try expect(defaults.object(forKey: duration.key) as? Double == duration.defaultMinutes,
                       "Normalization replaces invalid preference with default")
            }
            let invalidNumbers: [Double] = [0, -0.1, -1, .nan, .infinity, -.infinity, .greatestFiniteMagnitude,
                                             duration.range.lowerBound.nextDown, duration.range.upperBound.nextUp]
            for value in invalidNumbers {
                try expect(duration.validatedMinutes(value) == nil, "Reject out-of-range/nonfinite duration: \(value)")
                defaults.set(value, forKey: duration.key)
                try expect(duration.minutes(in: defaults) == duration.defaultMinutes,
                       "External invalid numbers cannot bypass safe reads")
                ReminderSettings.normalize(in: defaults)
                try expect(defaults.object(forKey: duration.key) as? Double == duration.defaultMinutes,
                       "Invalid numeric preferences are repaired")
            }
            for value in [duration.range.lowerBound, duration.range.upperBound, duration.defaultMinutes, 1.25] {
                defaults.set(value, forKey: duration.key)
                ReminderSettings.normalize(in: defaults)
                try expect(defaults.object(forKey: duration.key) as? Double == value && duration.minutes(in: defaults) == value,
                       "Preserve legal Double preferences exactly, including boundaries")
                try expect(duration.parsedMinutes(" \(value)\n") == value, "UI shares stored-number validation")
            }
            for text in ["", " ", "true", "NaN", "inf", "1e309", "0", "-2", "\(duration.range.upperBound + 1)"] {
                try expect(duration.parsedMinutes(text) == nil, "Reject invalid settings field input: \(text)")
            }
            defaults.set(1, forKey: duration.key)
            try expect(duration.minutes(in: defaults) == 1, "Numeric one is accepted; Boolean true is rejected")
            try expect(duration.validatedMinutes(NSNumber(value: 2.5)) == 2.5, "NSNumber numeric preferences remain supported")
        }
        defaults.set(45.125, forKey: Duration.work.key)
        defaults.set(false, forKey: Duration.rest.key)
        ReminderSettings.normalize(in: defaults)
        try expect(Duration.work.minutes(in: defaults) == 45.125 && Duration.rest.minutes(in: defaults) == 2,
               "Repair one invalid preference without changing another legal value")

        try expect(ReminderSettings.formatMinutes(30) == "30" && ReminderSettings.formatMinutes(0.1) == "0.1" &&
               ReminderSettings.formatMinutes(2.5) == "2.5", "Normal minute formatting is preserved")
        for invalid in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -1, Double(Int.max)] {
            try expect(ReminderSettings.formatMinutes(invalid) == "0", "Unsafe minute conversions have a finite fallback")
        }
        try expect(ReminderSettings.formatMinutes(Double(Int.max).nextDown) == String(Int(Double(Int.max).nextDown)),
               "Largest safely representable integer conversion works")
        try expect(ReminderSettings.countdownText(6.1) == "00:07" && ReminderSettings.countdownText(300) == "05:00",
               "Countdown rounds up and preserves the five-minute policy")
        try expect(ReminderSettings.restClockText(59.9) == "00:59" && ReminderSettings.restClockText(3601) == "01:00:01",
               "Elapsed clock rounds down and includes hours")
        for invalid in [Double.nan, .infinity, -.infinity, -1] {
            try expect(ReminderSettings.safeSeconds(invalid) == 0 && ReminderSettings.countdownText(invalid) == "00:00",
                   "Invalid clock values cannot trap or produce negative clocks")
        }
        let maximum = Int(Double(Int.max).nextDown)
        try expect(ReminderSettings.safeSeconds(.greatestFiniteMagnitude, rounding: .up) == maximum,
               "Huge finite clocks clamp before Int conversion")
        let tail = maximum % 60 < 10 ? "0\(maximum % 60)" : String(maximum % 60)
        try expect(ReminderSettings.countdownText(.greatestFiniteMagnitude) == "\(maximum / 60):\(tail)",
               "Large countdowns do not truncate through C Int formatting")
        try expect(!ReminderSettings.restClockText(.greatestFiniteMagnitude).isEmpty, "Huge elapsed clock remains safe")
        defaults.removePersistentDomain(forName: suite)
        try expect(defaults.persistentDomain(forName: suite)?.isEmpty != false, "Clean up only the test's unique suite")
        print("PASS: isolated defaults, invalid types including NSNumber Bool, finite range boundaries, legal-value preservation, shared UI parsing, safe minute/clock formatting, and suite cleanup")
    }
}
