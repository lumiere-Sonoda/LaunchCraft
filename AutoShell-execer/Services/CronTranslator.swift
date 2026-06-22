//
//  CronTranslator.swift
//  LaunchCraft
//
//  cron 式 (5フィールド) を launchd のスケジュールへ変換する。
//
//  方針:
//   - 各フィールドを「許可される値の集合」に展開する。* は nil（ワイルドカード）。
//   - StartCalendarInterval は「ワイルドカードでないフィールドだけ」の直積で生成する。
//     launchd は省略したフィールドを毎回マッチ扱いするので、これで cron と同じ意味になる。
//     例: */5 * * * * → {Minute:0},{Minute:5},...,{Minute:55} の 12 個（壁時計に整列）。
//   - 全フィールドが * の場合は「毎分」なので StartInterval=60 にする。
//

import Foundation

/// launchd 用に変換したスケジュール
enum LaunchdSchedule: Equatable {
    case interval(Int)                  // StartInterval（秒）
    case calendar([[String: Int]])      // StartCalendarInterval の配列
}

struct CronParseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum CronTranslator {

    /// 1つのフィールドが取りうる値の集合に変換する。
    /// `*` の場合は nil（ワイルドカード）を返す。
    /// 対応: `*`, 数値, `a,b,c`, `a-b`, `*/n`, `a-b/n`
    static func expandField(_ field: String, min: Int, max: Int) throws -> Set<Int>? {
        let trimmed = field.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            throw CronParseError(message: String(localized: "フィールドが空です"))
        }
        if trimmed == "*" {
            return nil
        }

        var result = Set<Int>()
        for part in trimmed.split(separator: ",") {
            try parsePart(String(part), min: min, max: max, into: &result)
        }
        if result.isEmpty {
            throw CronParseError(message: String(localized: "cron.err.unparsable", defaultValue: "値が解釈できません: \(field)"))
        }
        return result
    }

    private static func parsePart(_ part: String, min: Int, max: Int, into result: inout Set<Int>) throws {
        // ステップ a-b/n または */n
        var rangePart = part
        var step = 1
        if let slash = part.firstIndex(of: "/") {
            let stepStr = String(part[part.index(after: slash)...])
            guard let s = Int(stepStr), s > 0 else {
                throw CronParseError(message: String(localized: "cron.err.step", defaultValue: "ステップ値が不正です: \(part)"))
            }
            step = s
            rangePart = String(part[..<slash])
        }

        var lower = min
        var upper = max
        if rangePart == "*" {
            // 全範囲
        } else if let dash = rangePart.firstIndex(of: "-") {
            let lo = String(rangePart[..<dash])
            let hi = String(rangePart[rangePart.index(after: dash)...])
            guard let l = Int(lo), let h = Int(hi) else {
                throw CronParseError(message: String(localized: "cron.err.range", defaultValue: "範囲が不正です: \(part)"))
            }
            lower = l
            upper = h
        } else {
            guard let v = Int(rangePart) else {
                throw CronParseError(message: String(localized: "cron.err.number", defaultValue: "数値が不正です: \(part)"))
            }
            lower = v
            upper = v
        }

        guard lower >= min, upper <= max, lower <= upper else {
            throw CronParseError(message: String(localized: "cron.err.outOfRange", defaultValue: "値が範囲外です(\(min)〜\(max)): \(part)"))
        }

        var v = lower
        while v <= upper {
            result.insert(v)
            v += step
        }
    }

    /// cron 式を 5 フィールドに分解して検証する。
    /// 戻り値: (minute, hour, dayOfMonth, month, dayOfWeek) それぞれ集合 or nil(=*)
    static func parse(_ expression: String) throws
        -> (minute: Set<Int>?, hour: Set<Int>?, dom: Set<Int>?, month: Set<Int>?, dow: Set<Int>?) {
        let fields = expression.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard fields.count == 5 else {
            throw CronParseError(message: String(localized: "cron は5つのフィールドが必要です（分 時 日 月 曜日）。例: */5 * * * *"))
        }
        let minute = try expandField(fields[0], min: 0, max: 59)
        let hour   = try expandField(fields[1], min: 0, max: 23)
        let dom    = try expandField(fields[2], min: 1, max: 31)
        let month  = try expandField(fields[3], min: 1, max: 12)
        var dow    = try expandField(fields[4], min: 0, max: 7)
        // cron では 7 も日曜。launchd の Weekday に合わせ 7 を 0 に寄せる。
        if var d = dow, d.contains(7) {
            d.remove(7)
            d.insert(0)
            dow = d
        }
        return (minute, hour, dom, month, dow)
    }

    /// cron 式を launchd スケジュールに変換する。
    static func toLaunchd(_ expression: String, maxEntries: Int = 500) throws -> LaunchdSchedule {
        let (minute, hour, dom, month, dow) = try parse(expression)

        // 全フィールドが * → 毎分
        if minute == nil && hour == nil && dom == nil && month == nil && dow == nil {
            return .interval(60)
        }

        // 各フィールドのキーと値集合（nil はワイルドカードなので除外）
        let pairs: [(key: String, values: [Int])] = [
            ("Minute",  minute),
            ("Hour",    hour),
            ("Day",     dom),
            ("Month",   month),
            ("Weekday", dow)
        ].compactMap { key, set in
            guard let set = set else { return nil }
            return (key, set.sorted())
        }

        // 直積のサイズを確認
        let total = pairs.reduce(1) { $0 * $1.values.count }
        guard total <= maxEntries else {
            throw CronParseError(message: String(localized: "cron.err.tooMany", defaultValue: "この cron 式は \(total) 個の実行時刻に展開され、多すぎます（上限 \(maxEntries)）。間隔(launchd)モードか、もっと絞った式をお使いください。"))
        }

        // ワイルドカードでないフィールドだけで直積を作る
        var entries: [[String: Int]] = [[:]]
        for (key, values) in pairs {
            var next: [[String: Int]] = []
            for base in entries {
                for v in values {
                    var dict = base
                    dict[key] = v
                    next.append(dict)
                }
            }
            entries = next
        }

        return .calendar(entries)
    }

    /// launchd「かんたん」モードのカレンダー設定を StartCalendarInterval の配列へ。
    static func calendarSchedule(from cal: CalendarSchedule) -> [[String: Int]] {
        switch cal.frequency {
        case .hourly:
            return [["Minute": cal.minute]]
        case .daily:
            return [["Hour": cal.hour, "Minute": cal.minute]]
        case .monthly:
            return [["Day": cal.day, "Hour": cal.hour, "Minute": cal.minute]]
        case .weekly:
            let days = cal.weekdays.isEmpty ? [1] : cal.weekdays.sorted()
            return days.map { ["Weekday": $0, "Hour": cal.hour, "Minute": cal.minute] }
        }
    }
}
