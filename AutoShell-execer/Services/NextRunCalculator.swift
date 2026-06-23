//
//  NextRunCalculator.swift
//  LaunchCraft
//
//  ShellJob のスケジュール設定から「次回実行予定時刻」を算出する。
//
//  - calendar/cron: Calendar.nextDate(after:matching:) で正確な次回時刻を求める
//  - interval: "今から N 秒後" を近似値として返す（実際は前回実行時刻によって変わる）
//

import Foundation

// 次回実行時刻を算出する純粋関数の集まり。状態を持たないため nonisolated。
nonisolated enum NextRunCalculator {

    // MARK: 次回実行日時

    static func nextRun(for job: ShellJob) -> Date? {
        guard job.enabled else { return nil }
        switch job.scheduleMode {
        case .launchd:
            return nextRunLaunchd(job)
        case .cron:
            guard let schedule = try? CronTranslator.toLaunchd(job.cronExpression) else { return nil }
            return nextRunFromSchedule(schedule)
        }
    }

    private static func nextRunLaunchd(_ job: ShellJob) -> Date? {
        switch job.launchdKind {
        case .interval:
            let seconds = max(1, job.intervalValue) * job.intervalUnit.multiplier
            return Date().addingTimeInterval(TimeInterval(seconds))
        case .calendar:
            let entries = CronTranslator.calendarSchedule(from: job.calendar)
            return nextCalendarDate(from: entries)
        }
    }

    private static func nextRunFromSchedule(_ schedule: LaunchdSchedule) -> Date? {
        switch schedule {
        case .interval(let secs):
            return Date().addingTimeInterval(TimeInterval(secs))
        case .calendar(let entries):
            return nextCalendarDate(from: entries)
        }
    }

    static func nextCalendarDate(from entries: [[String: Int]]) -> Date? {
        let now = Date()
        let cal = Calendar.current
        return entries.compactMap { entry -> Date? in
            var comps = DateComponents()
            if let m  = entry["Minute"]  { comps.minute  = m }
            if let h  = entry["Hour"]    { comps.hour    = h }
            if let d  = entry["Day"]     { comps.day     = d }
            if let mo = entry["Month"]   { comps.month   = mo }
            // launchd Weekday: 0=日、Calendar.weekday: 1=日 → +1
            if let wd = entry["Weekday"] { comps.weekday = wd + 1 }
            // .strict: 存在しない日（例: 31日が無い月）には丸めず次の厳密一致へ進む。
            // launchd 自身もそうした月はスキップするため、挙動を一致させる。
            return cal.nextDate(after: now, matching: comps, matchingPolicy: .strict)
        }.min()
    }

    // MARK: 表示用ラベル

    /// 次回実行時刻を人間向けの短い文字列で返す。
    static func nextRunLabel(for job: ShellJob) -> String? {
        guard let date = nextRun(for: job) else { return nil }
        return relativeLabel(for: date)
    }

    /// 次回実行 Date を人間向けの短い相対表記へ整形する（毎秒変わるが軽い処理）。
    /// 重い `nextRun(for:)`（Calendar.nextDate）はキャッシュ側で済ませ、ここは整形のみ。
    static func relativeLabel(for date: Date) -> String {
        let now = Date()
        let diff = date.timeIntervalSince(now)

        if diff < 60 {
            return String(localized: "nextRun.lessThan1min", defaultValue: "1分以内")
        }
        if diff < 3600 {
            let mins = Int(diff / 60)
            return String(localized: "nextRun.minutes", defaultValue: "あと \(mins)分")
        }
        if Calendar.current.isDateInToday(date) {
            return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        }
        if Calendar.current.isDateInTomorrow(date) {
            let t = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
            return String(localized: "nextRun.tomorrow", defaultValue: "明日 \(t)")
        }
        return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }
}
