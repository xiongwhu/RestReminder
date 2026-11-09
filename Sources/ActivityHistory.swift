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

enum ActivityKind: String, Codable { case work, rest }

struct ActivityRecord: Codable, Equatable {
    var start: Date
    var end: Date
    var kind: ActivityKind
    var reason: String
}

/// Presentation only: archives continue to store work/rest records in the v1 schema.
enum ActivityDisplayKind: String { case work, rest, away }

struct ActivityDisplayInterval {
    let start: Date
    let end: Date
    let kind: ActivityDisplayKind
    let reason: String

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Detail rows only: retain original classified members and exclude unobserved gaps from duration.
struct ActivityDetailGroup {
    let intervals: [ActivityDisplayInterval]

    // Only grouped() constructs groups, always with at least one valid interval.
    private init(intervals: [ActivityDisplayInterval]) { self.intervals = intervals }

    var start: Date { intervals[0].start }
    var end: Date { intervals[intervals.count - 1].end }
    var kind: ActivityDisplayKind { intervals[0].kind }
    var reason: String {
        var seen = Set<String>()
        return intervals.map { $0.reason }.filter { seen.insert($0).inserted }.joined(separator: "；")
    }
    var duration: TimeInterval { intervals.reduce(0) { $0 + $1.duration } }
    var gapDuration: TimeInterval { max(0, end.timeIntervalSince(start) - duration) }

    func contains(_ interval: ActivityDisplayInterval) -> Bool {
        intervals.contains {
            $0.start == interval.start && $0.end == interval.end &&
            $0.kind == interval.kind && $0.reason == interval.reason
        }
    }

    static func grouped(_ intervals: [ActivityDisplayInterval], maximumGap: TimeInterval = 120,
                        calendar: Calendar = .current) -> [ActivityDetailGroup] {
        let limit = maximumGap.isFinite && maximumGap >= 0 ? maximumGap : 0
        // An invalid start cannot be placed chronologically, so conservatively keep every member separate.
        let unplacedBarrier = intervals.contains { !$0.start.timeIntervalSince1970.isFinite }
        let ordered = intervals.enumerated().sorted { left, right in
            let lhs = left.element.start.timeIntervalSince1970
            let rhs = right.element.start.timeIntervalSince1970
            if lhs.isFinite != rhs.isFinite { return lhs.isFinite }
            if lhs.isFinite, lhs != rhs { return lhs < rhs }
            return left.offset < right.offset
        }.map { $0.element }
        var groups: [ActivityDetailGroup] = []
        var members: [ActivityDisplayInterval] = []
        var occupiedUntil: Date?
        func flush() {
            if !members.isEmpty { groups.append(ActivityDetailGroup(intervals: members)); members = [] }
        }
        for interval in ordered {
            guard interval.start.timeIntervalSince1970.isFinite,
                  interval.end.timeIntervalSince1970.isFinite,
                  interval.duration.isFinite, interval.duration > 0 else {
                flush() // Malformed input is a barrier, never a member or a bridge.
                continue
            }
            let overlaps = occupiedUntil.map { interval.start < $0 } ?? false
            occupiedUntil = max(occupiedUntil ?? interval.end, interval.end)
            guard !overlaps, !unplacedBarrier,
                  let day = calendar.dateInterval(of: .day, for: interval.start), interval.end <= day.end else {
                flush()
                groups.append(ActivityDetailGroup(intervals: [interval]))
                continue
            }
            if let previous = members.last {
                let gap = interval.start.timeIntervalSince(previous.end)
                if previous.kind != interval.kind || gap < 0 || gap > limit ||
                    !calendar.isDate(members[0].start, inSameDayAs: interval.start) {
                    flush()
                }
            }
            members.append(interval)
        }
        flush()
        return groups
    }
}

struct ActivityDay {
    /// All positive day-clipped raw intervals, including fractions hidden in the UI.
    let intervals: [ActivityRecord]
    let displayIntervals: [ActivityDisplayInterval]
    /// Group all positive classified fragments before hiding groups with less than one recorded second.
    let detailGroups: [ActivityDetailGroup]
    let workSeconds: TimeInterval
    let restSeconds: TimeInterval
    let awaySeconds: TimeInterval
    /// Closed short rests meeting the current threshold, counted on their local end date.
    let completedRestCount: Int
    /// Longest single day-clipped work interval; never joined across rests or gaps.
    let longestWorkSeconds: TimeInterval
    let ongoingStart: Date?
}

struct ActivityWeekDay {
    enum Status { case past, partial, future }
    let range: DateInterval
    let summary: ActivityDay
    let status: Status
}

struct ActivityWeek {
    let range: DateInterval
    let days: [ActivityWeekDay]
    var workSeconds: TimeInterval { days.reduce(0) { $0 + $1.summary.workSeconds } }
    var restSeconds: TimeInterval { days.reduce(0) { $0 + $1.summary.restSeconds } }
    var awaySeconds: TimeInterval { days.reduce(0) { $0 + $1.summary.awaySeconds } }
}

/// Tests can inject an in-memory preference store. Non-default archives never use real preferences implicitly.
protocol ActivityHistoryPreferences: AnyObject {
    var historyRetentionDays: Int { get set }
}

extension UserDefaults: ActivityHistoryPreferences {
    var historyRetentionDays: Int {
        get { integer(forKey: "historyRetentionDays") }
        set { set(newValue, forKey: "historyRetentionDays") }
    }
}

struct ActivityDeletionPreview {
    /// Count each affected source interval once, even when it leaves two retained fragments.
    let affectedIntervalCount: Int
    let removedSeconds: TimeInterval
    /// Actual first/last removed timestamps; gaps inside this envelope are not counted as time.
    let affectedRange: DateInterval?
    let retainedFragmentCount: Int
    /// Frozen latest observation. Recording after this point survives confirmation.
    let cutPoint: Date
    fileprivate let range: DateInterval
    fileprivate let owner: UUID
    fileprivate let revision: Int
    fileprivate let intersections: [ActivityRecord]
    fileprivate let clearsAll: Bool
}

struct ActivityRetentionPreview {
    let days: Int
    let cutoff: Date?
    let deletion: ActivityDeletionPreview?
    fileprivate let owner: UUID
    fileprivate let oldDays: Int
}

enum ActivityHistoryError: LocalizedError {
    case protectedArchive, stalePreview, invalidRetention
    var errorDescription: String? {
        switch self {
        case .protectedArchive: return "原历史文件无法读取，删除及自动清理已停用，以免覆盖原文件。"
        case .stalePreview: return "记录已变化，请重新预览后确认。"
        case .invalidRetention: return "请选择永久保留、30、90 或 365 天。"
        }
    }
}

/// Separate from reminder timers: resetting or pausing reminders cannot erase history.
final class ActivityHistory {
    private struct Archive: Codable {
        var version = 1
        var records: [ActivityRecord]
    }
    private struct EditPlan {
        var records: [ActivityRecord]
        var current: ActivityRecord?
        var intersections: [ActivityRecord]
        var retainedFragments: Int
        var recordingFloor: Date?
    }
    private var records: [ActivityRecord] = []
    private var current: ActivityRecord?
    private var observedSince: Date?
    private var recordingFloor: Date?
    private var lastSample: Date?
    private var lastUptime: TimeInterval?
    private var lastSaved: Date?
    private var suspended = false
    private let storageURL: URL?
    private let preferences: ActivityHistoryPreferences?
    private let archiveWriter: (Data, URL) throws -> Void
    private let identity = UUID()
    private var editRevision = 0
    private var canPersist = true
    private(set) var persistenceError: String?
    private(set) var retentionDays: Int
    var allowsDestructiveChanges: Bool { canPersist }
    static let retentionChoices = [0, 30, 90, 365]

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RestReminder", isDirectory: true)
            .appendingPathComponent("activity-history.json")
    }

    init(storageURL: URL? = ActivityHistory.defaultURL, retentionDays: Int? = nil,
         preferences: ActivityHistoryPreferences? = nil,
         archiveWriter: ((Data, URL) throws -> Void)? = nil) {
        self.storageURL = storageURL
        let store = preferences ?? (storageURL == Self.defaultURL ? UserDefaults.standard : nil)
        self.preferences = store
        let choice = retentionDays ?? store?.historyRetentionDays ?? 0
        self.retentionDays = Self.retentionChoices.contains(choice) ? choice : 0
        self.archiveWriter = archiveWriter ?? { data, url in
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        guard let storageURL, FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let archive = try decoder.decode(Archive.self, from: Data(contentsOf: storageURL))
            guard archive.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
            var previousEnd: Date?
            for record in archive.records {
                guard record.start.timeIntervalSince1970.isFinite,
                      record.end.timeIntervalSince1970.isFinite,
                      record.end > record.start,
                      previousEnd.map({ record.start >= $0 }) ?? true else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                previousEnd = record.end
            }
            records = archive.records
            // A persisted checkpoint is closed. Never count time while the app was stopped.
        } catch {
            canPersist = false
            persistenceError = "历史文件无法读取，已保留原文件；本次记录暂存内存。\(error.localizedDescription)"
        }
    }

    func sample(at date: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
                idle: TimeInterval, restThreshold: TimeInterval) {
        guard idle.isFinite, idle >= 0, restThreshold.isFinite, restThreshold > 0 else { return }
        if let lastSample, date < lastSample { return } // Avoid negative or overlapping spans on clock rollback.
        if current == nil, let lastEnd = records.last?.end, date < lastEnd { return }
        if let recordingFloor, date < recordingFloor { return }
        if observedSince == nil { observedSince = date }
        if !suspended, let lastUptime, uptime - lastUptime > 10 {
            if let lastSample { close(at: lastSample) }
            observedSince = date
        }
        lastSample = date
        lastUptime = uptime
        if suspended {
            current?.end = date
            checkpoint(at: date)
            return
        }
        let inputDate = date.addingTimeInterval(-idle)
        if idle >= restThreshold {
            let restStart = max(observedSince ?? date, inputDate, recordingFloor ?? .distantPast)
            if current?.kind != .rest {
                transition(to: .rest, at: max(current?.start ?? restStart, restStart),
                           now: date, reason: "无键鼠操作")
            } else { current?.end = date }
        } else if current?.kind == .work {
            current?.end = date
        } else if idle <= 2 {
            let start = max(current?.start ?? date, inputDate, recordingFloor ?? .distantPast)
            transition(to: .work, at: start, now: date, reason: "键鼠活动（含短暂停顿）")
        } else {
            current?.end = date
        }
        checkpoint(at: date)
    }

    func suspend(at date: Date = Date(), reason: String = "系统休眠 / 会话离开") {
        guard !suspended, date >= (lastSample ?? .distantPast), date >= (recordingFloor ?? .distantPast) else { return }
        if current == nil, let lastEnd = records.last?.end, date < lastEnd { return }
        suspended = true
        observedSince = observedSince ?? date
        if current?.kind == .rest {
            // Already resting: keep the original inactivity start time.
            if let end = current?.end { current?.end = max(end, date) }
        } else {
            transition(to: .rest, at: date, now: date, reason: reason)
        }
        lastSample = date
        persist(at: date)
    }

    func resume(at date: Date = Date()) {
        guard suspended, date >= (lastSample ?? .distantPast) else { return }
        if let end = current?.end { current?.end = max(end, date) }
        suspended = false
        lastSample = date
        lastUptime = nil
        persist(at: date)
    }

    func finish(at date: Date = Date()) {
        close(at: max(lastSample ?? date, date))
        persist(at: date)
    }

    func day(_ date: Date, now: Date = Date(), calendar: Calendar = .current,
             restThreshold: TimeInterval = 120) -> ActivityDay {
        guard let range = calendar.dateInterval(of: .day, for: date) else {
            return ActivityDay(intervals: [], displayIntervals: [], detailGroups: [], workSeconds: 0, restSeconds: 0,
                               awaySeconds: 0, completedRestCount: 0, longestWorkSeconds: 0, ongoingStart: nil)
        }
        let all = records + (current.map { [$0] } ?? [])
        var clipped: [ActivityRecord] = []
        var displayed: [ActivityDisplayInterval] = []
        var classified: [ActivityDisplayInterval] = []
        var work: TimeInterval = 0
        var rest: TimeInterval = 0
        var away: TimeInterval = 0
        var longestWork: TimeInterval = 0
        var completedRests = 0
        for (index, record) in all.enumerated() {
            let rawDuration = record.end.timeIntervalSince(record.start)
            // Classify the whole raw span before clipping: even a short midnight fragment is away.
            let kind = Self.displayKind(record)
            if index < records.count, kind == .rest,
               restThreshold.isFinite, restThreshold > 0, rawDuration >= restThreshold,
               record.end >= range.start, record.end < range.end, record.end <= now {
                completedRests += 1
            }
            let start = max(record.start, range.start)
            let end = min(record.end, range.end, now)
            guard end > start else { continue }
            let duration = end.timeIntervalSince(start)
            clipped.append(ActivityRecord(start: start, end: end, kind: record.kind, reason: record.reason))
            switch kind {
            case .work:
                work += duration
                longestWork = max(longestWork, duration)
            case .rest: rest += duration
            case .away: away += duration
            }
            let fragment = ActivityDisplayInterval(start: start, end: end, kind: kind, reason: record.reason)
            classified.append(fragment)
            // The timeline still hides subsecond intervals; detail grouping must see them as members or barriers.
            if duration >= 1 { displayed.append(fragment) }
        }
        let ongoing = current.flatMap { record -> Date? in
            guard record.start < range.end, record.end > range.start, now >= range.start, now < range.end else { return nil }
            return max(record.start, range.start)
        }
        let details = ActivityDetailGroup.grouped(classified, calendar: calendar).filter { $0.duration >= 1 }
        return ActivityDay(intervals: clipped, displayIntervals: displayed, detailGroups: details, workSeconds: work, restSeconds: rest,
                           awaySeconds: away, completedRestCount: completedRests,
                           longestWorkSeconds: longestWork, ongoingStart: ongoing)
    }

    /// Monday–Sunday, independent of the locale's first weekday. Each day has its real local duration.
    func week(_ date: Date, now: Date = Date(), calendar: Calendar = .current,
              restThreshold: TimeInterval = 120) -> ActivityWeek {
        let dayStart = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: dayStart) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -offset, to: dayStart)!
        let end = calendar.date(byAdding: .day, value: 7, to: monday)!
        let days = (0..<7).map { index -> ActivityWeekDay in
            let start = calendar.date(byAdding: .day, value: index, to: monday)!
            let range = calendar.dateInterval(of: .day, for: start)!
            let status: ActivityWeekDay.Status = now < range.start ? .future : (now < range.end ? .partial : .past)
            return ActivityWeekDay(range: range,
                summary: day(start, now: now, calendar: calendar, restThreshold: restThreshold), status: status)
        }
        return ActivityWeek(range: DateInterval(start: monday, end: end), days: days)
    }

    /// UTF-8, RFC 4180 quoting, CRLF rows, all positive fragments (including subsecond intervals).
    /// Category is based on the whole source span. `ongoing` describes the source, even for a past-day fragment.
    func csv(in range: DateInterval, now: Date = Date(), calendar: Calendar = .current,
             includeBOM: Bool = false) -> Data {
        var rows = [["start", "end", "duration_seconds", "category", "reason", "ongoing"].map(Self.csvField).joined(separator: ",")]
        let all = records + (current.map { [$0] } ?? [])
        for (index, record) in all.enumerated() {
            let start = max(record.start, range.start)
            let end = min(record.end, range.end, now)
            guard end > start else { continue }
            let fields = [Self.csvTimestamp(start, timeZone: calendar.timeZone),
                          Self.csvTimestamp(end, timeZone: calendar.timeZone),
                          Self.decimalSeconds(end.timeIntervalSince(start)), Self.displayKind(record).rawValue,
                          record.reason, index == records.count ? "true" : "false"]
            rows.append(fields.map(Self.csvField).joined(separator: ","))
        }
        return Data(((includeBOM ? "\u{FEFF}" : "") + rows.joined(separator: "\r\n") + "\r\n").utf8)
    }

    /// This method is read-only. A nil range means every historical span through the latest observation.
    func previewDeletion(in range: DateInterval? = nil, at date: Date = Date()) throws -> ActivityDeletionPreview {
        guard canPersist else { throw ActivityHistoryError.protectedArchive }
        let cutPoint = current != nil ? min(date, lastSample ?? current!.end) : max(date, records.last?.end ?? date)
        let start = range?.start ?? .distantPast
        let end = min(range?.end ?? cutPoint, cutPoint)
        let effective = DateInterval(start: min(start, end), end: end)
        let plan = deletionPlan(in: effective)
        let first = plan.intersections.first?.start
        let last = plan.intersections.last?.end
        return ActivityDeletionPreview(affectedIntervalCount: plan.intersections.count,
            removedSeconds: plan.intersections.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) },
            affectedRange: first.flatMap { first in last.map { DateInterval(start: first, end: $0) } },
            retainedFragmentCount: plan.retainedFragments, cutPoint: cutPoint, range: effective,
            owner: identity, revision: editRevision, intersections: plan.intersections, clearsAll: range == nil)
    }

    /// The atomic write must succeed before any records, recording boundaries or preferences change.
    func delete(_ preview: ActivityDeletionPreview) throws {
        do {
            let plan = try validatedPlan(preview)
            try writeSnapshot(records: plan.records, current: plan.current)
            commit(plan, at: preview.cutPoint, clearsAll: preview.clearsAll)
        } catch {
            reportMutationError(error)
            throw error
        }
    }

    /// Rolling local calendar days, preserving the local clock time through DST transitions.
    func previewRetention(days: Int, at date: Date = Date(), calendar: Calendar = .current) throws -> ActivityRetentionPreview {
        guard Self.retentionChoices.contains(days) else { throw ActivityHistoryError.invalidRetention }
        if days == 0 {
            return ActivityRetentionPreview(days: 0, cutoff: nil, deletion: nil, owner: identity, oldDays: retentionDays)
        }
        guard canPersist else { throw ActivityHistoryError.protectedArchive }
        let cutoff = calendar.date(byAdding: .day, value: -days, to: date)!
        let deletion = try previewDeletion(in: DateInterval(start: .distantPast, end: cutoff), at: date)
        return ActivityRetentionPreview(days: days, cutoff: cutoff, deletion: deletion, owner: identity, oldDays: retentionDays)
    }

    func applyRetention(_ preview: ActivityRetentionPreview) throws {
        guard preview.owner == identity, preview.oldDays == retentionDays else { throw ActivityHistoryError.stalePreview }
        if let deletion = preview.deletion { try delete(deletion) }
        retentionDays = preview.days
        preferences?.historyRetentionDays = preview.days
    }

    /// Startup itself never rewrites an archive. Later checkpoints honor an already persisted finite choice.
    func prune(at date: Date = Date(), calendar: Calendar = .current) throws {
        guard retentionDays > 0 else { return }
        let preview = try previewRetention(days: retentionDays, at: date, calendar: calendar)
        if let deletion = preview.deletion, deletion.affectedIntervalCount > 0 { try delete(deletion) }
    }

    private static func displayKind(_ record: ActivityRecord) -> ActivityDisplayKind {
        record.kind == .work ? .work : (record.end.timeIntervalSince(record.start) >= 3600 ? .away : .rest)
    }

    private static func decimalSeconds(_ seconds: TimeInterval) -> String {
        var value = String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), seconds)
        while value.last == "0" { value.removeLast() }
        if value.last == "." { value.removeLast() }
        return value
    }

    static func csvField(_ value: String) -> String {
        let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
        let unsafe = first.map { "=+-@".contains($0) } ?? false
        let protected = (unsafe || value.first == "\t" || value.first == "\r" || value.first == "\n") ? "'" + value : value
        return "\"" + protected.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func csvTimestamp(_ date: Date, timeZone: TimeZone) -> String {
        var whole = floor(date.timeIntervalSince1970)
        var micros = Int(((date.timeIntervalSince1970 - whole) * 1_000_000).rounded())
        if micros == 1_000_000 { whole += 1; micros = 0 }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let offset = timeZone.secondsFromGMT(for: date)
        let zone = String(format: "%@%02d:%02d", offset < 0 ? "-" : "+", abs(offset) / 3600, abs(offset) % 3600 / 60)
        return formatter.string(from: Date(timeIntervalSince1970: whole)) + String(format: ".%06d", micros) + zone
    }

    private func deletionPlan(in range: DateInterval) -> EditPlan {
        var kept: [ActivityRecord] = []
        var intersections: [ActivityRecord] = []
        var fragments = 0
        func subtract(_ record: ActivityRecord) -> [ActivityRecord]? {
            let start = max(record.start, range.start)
            let end = min(record.end, range.end)
            guard end > start else { return nil }
            var overlap = record
            overlap.start = start; overlap.end = end
            intersections.append(overlap)
            var pieces: [ActivityRecord] = []
            if record.start < start { var prefix = record; prefix.end = start; pieces.append(prefix) }
            if end < record.end { var suffix = record; suffix.start = end; pieces.append(suffix) }
            fragments += pieces.count
            return pieces
        }
        for record in records { kept.append(contentsOf: subtract(record) ?? [record]) }
        var nextCurrent = current
        var floor: Date?
        if let record = current, let pieces = subtract(record) {
            floor = min(record.end, range.end)
            for piece in pieces where piece.start < range.start { kept.append(piece) }
            if let suffix = pieces.last, suffix.start >= range.end {
                nextCurrent = suffix
            } else {
                nextCurrent = ActivityRecord(start: floor!, end: floor!, kind: record.kind, reason: record.reason)
            }
        }
        return EditPlan(records: kept, current: nextCurrent, intersections: intersections,
                        retainedFragments: fragments, recordingFloor: floor)
    }

    private func validatedPlan(_ preview: ActivityDeletionPreview) throws -> EditPlan {
        guard canPersist else { throw ActivityHistoryError.protectedArchive }
        let plan = deletionPlan(in: preview.range)
        guard preview.owner == identity, preview.revision == editRevision,
              plan.intersections == preview.intersections else { throw ActivityHistoryError.stalePreview }
        return plan
    }

    private func commit(_ plan: EditPlan, at date: Date, clearsAll: Bool) {
        records = plan.records
        current = plan.current
        if let floor = plan.recordingFloor ?? (clearsAll ? date : nil) {
            recordingFloor = max(recordingFloor ?? .distantPast, floor)
            observedSince = max(observedSince ?? .distantPast, floor)
        }
        editRevision += 1
        lastSaved = date
        persistenceError = nil
    }

    private func transition(to kind: ActivityKind, at start: Date, now: Date, reason: String) {
        close(at: start)
        current = ActivityRecord(start: start, end: max(start, now), kind: kind, reason: reason)
        persist(at: now)
    }

    private func close(at end: Date) {
        if var value = current {
            value.end = max(value.start, end)
            if value.end > value.start { records.append(value) }
        }
        current = nil
    }

    private func checkpoint(at date: Date) {
        if lastSaved.map({ date.timeIntervalSince($0) >= 30 }) ?? true { persist(at: date) }
    }

    private func writeSnapshot(records: [ActivityRecord], current: ActivityRecord?) throws {
        guard canPersist else { throw ActivityHistoryError.protectedArchive }
        guard let storageURL else { return }
        let snapshot = records + (current.flatMap { $0.end > $0.start ? [$0] : nil } ?? [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(Archive(records: snapshot))
        try archiveWriter(data, storageURL)
    }

    private func reportMutationError(_ error: Error) {
        persistenceError = "未更改历史记录：\(error.localizedDescription)"
    }

    private func persist(at date: Date) {
        guard canPersist else { return }
        do {
            // Pruning uses the same staged write as explicit deletion. A failed write retains every old span.
            if retentionDays > 0 {
                let preview = try previewRetention(days: retentionDays, at: date)
                if let deletion = preview.deletion, deletion.affectedIntervalCount > 0 {
                    try delete(deletion)
                    return
                }
            }
            try writeSnapshot(records: records, current: current)
            lastSaved = date
            persistenceError = nil
        } catch {
            persistenceError = "本地保存失败，记录暂存内存：\(error.localizedDescription)"
        }
    }
}
