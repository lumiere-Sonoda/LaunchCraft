//
//  ShellJob.swift
//  LaunchCraft
//
//  1つのスケジュール実行ジョブを表すモデル。
//  このアプリの真実の源で、ここから launchd の plist を生成する。
//
//  表示文字列は String(localized:) を通し、String Catalog で en/ja を切り替える。
//

import Foundation

// MARK: - 曜日名（ローカライズ）

/// 曜日の短い名前。0=日 〜 6=土。
/// 「日」「月」などは他の語（日付の「日」・曜日の「月」など）と衝突するため、
/// 文脈ごとに独立したキーを与えて翻訳する。
nonisolated enum WeekdaySymbols {
    static func short(_ index: Int) -> String {
        switch ((index % 7) + 7) % 7 {
        case 0:  return String(localized: "weekday.short.sun", defaultValue: "日")
        case 1:  return String(localized: "weekday.short.mon", defaultValue: "月")
        case 2:  return String(localized: "weekday.short.tue", defaultValue: "火")
        case 3:  return String(localized: "weekday.short.wed", defaultValue: "水")
        case 4:  return String(localized: "weekday.short.thu", defaultValue: "木")
        case 5:  return String(localized: "weekday.short.fri", defaultValue: "金")
        default: return String(localized: "weekday.short.sat", defaultValue: "土")
        }
    }
    static var all: [String] { (0..<7).map(short) }
}

// MARK: - 補助的な列挙型

/// スクリプトの指定方法
nonisolated enum ScriptKind: String, Codable, CaseIterable, Identifiable {
    case inline   // アプリ内に書いたコード
    case file     // 既存の .sh などのファイルを指定
    var id: String { rawValue }
    var label: String {
        switch self {
        case .inline: return String(localized: "インラインスクリプト")
        case .file:   return String(localized: "ファイルを指定")
        }
    }
}

/// スケジュールの入力モード
nonisolated enum ScheduleMode: String, Codable, CaseIterable, Identifiable {
    case launchd  // わかりやすいビルダー
    case cron     // cron 式
    var id: String { rawValue }
    var label: String {
        switch self {
        case .launchd: return String(localized: "launchd（かんたん）")
        case .cron:    return String(localized: "cron 式")
        }
    }
}

/// launchd モードのスケジュール種別
nonisolated enum LaunchdKind: String, Codable, CaseIterable, Identifiable {
    case interval  // 一定間隔ごと (StartInterval)
    case calendar  // 決まった時刻 (StartCalendarInterval)
    var id: String { rawValue }
    var label: String {
        switch self {
        case .interval: return String(localized: "一定間隔ごと")
        case .calendar: return String(localized: "決まった時刻に")
        }
    }
}

/// 間隔の単位
nonisolated enum IntervalUnit: String, Codable, CaseIterable, Identifiable {
    case seconds, minutes, hours, days
    var id: String { rawValue }
    var label: String {
        switch self {
        case .seconds: return String(localized: "unit.seconds", defaultValue: "秒")
        case .minutes: return String(localized: "unit.minutes", defaultValue: "分")
        case .hours:   return String(localized: "unit.hours",   defaultValue: "時間")
        case .days:    return String(localized: "unit.days",    defaultValue: "日")
        }
    }
    var multiplier: Int {
        switch self {
        case .seconds: return 1
        case .minutes: return 60
        case .hours:   return 3600
        case .days:    return 86_400
        }
    }
}

/// カレンダー実行の頻度
nonisolated enum CalendarFrequency: String, Codable, CaseIterable, Identifiable {
    case hourly  // 毎時 MM 分
    case daily   // 毎日 HH:MM
    case weekly  // 毎週 指定曜日 HH:MM
    case monthly // 毎月 指定日 HH:MM
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hourly:  return String(localized: "毎時")
        case .daily:   return String(localized: "毎日")
        case .weekly:  return String(localized: "毎週")
        case .monthly: return String(localized: "毎月")
        }
    }
}

/// 環境変数の1エントリ
nonisolated struct EnvVar: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var key: String = ""
    var value: String = ""
}

/// カレンダー実行の詳細設定
nonisolated struct CalendarSchedule: Codable, Hashable {
    var frequency: CalendarFrequency = .daily
    var minute: Int = 0
    var hour: Int = 9
    /// 0=日 〜 6=土
    var weekdays: Set<Int> = [1]
    /// 1〜31
    var day: Int = 1
}

// MARK: - ShellJob 本体

// アプリの真実の源となるデータモデル。UI を一切触らず、launchctl 実行などの
// バックグラウンド（nonisolated）処理からも参照するため、既定の MainActor 分離を外す。
nonisolated struct ShellJob: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = "新しいジョブ"
    var enabled: Bool = true

    // --- スクリプト ---
    var scriptKind: ScriptKind = .inline
    /// 実行に使うインタプリタ。file モードで空文字なら「ファイルを直接実行」。
    var interpreter: String = "/bin/zsh"
    var inlineCode: String = "#!/bin/zsh\n\necho \"Hello from LaunchCraft at $(date)\"\n"
    var scriptFilePath: String = ""
    var arguments: [String] = []
    var workingDirectory: String = ""
    var environment: [EnvVar] = []

    // --- スケジュール ---
    var scheduleMode: ScheduleMode = .launchd
    var launchdKind: LaunchdKind = .calendar
    var intervalValue: Int = 30
    var intervalUnit: IntervalUnit = .minutes
    var calendar: CalendarSchedule = CalendarSchedule()
    var cronExpression: String = "*/5 * * * *"

    // --- オプション ---
    var runAtLoad: Bool = false
    var keepAlive: Bool = false

    // --- メタdata ---
    var createdAt: Date = Date()
    var lastModified: Date = Date()

    // MARK: 派生プロパティ

    /// launchd のラベル（ジョブの一意な識別子）
    var label: String { "com.launchcraft.\(id.uuidString.lowercased())" }

    /// LaunchAgents 内の plist パス
    var plistURL: URL {
        Paths.launchAgentsDir.appendingPathComponent("\(label).plist")
    }

    /// インラインコードを書き出す .sh のパス
    var inlineScriptURL: URL {
        Paths.scriptsDir.appendingPathComponent("\(id.uuidString.lowercased()).sh")
    }

    /// メタデータ JSON のパス
    var metadataURL: URL {
        Paths.jobsDir.appendingPathComponent("\(id.uuidString.lowercased()).json")
    }

    var stdoutLogURL: URL {
        Paths.logsDir.appendingPathComponent("\(id.uuidString.lowercased()).out.log")
    }

    var stderrLogURL: URL {
        Paths.logsDir.appendingPathComponent("\(id.uuidString.lowercased()).err.log")
    }

    /// 実際に実行されるパス（inline なら .sh、file ならそのパス）
    var resolvedScriptPath: String {
        switch scriptKind {
        case .inline: return inlineScriptURL.path
        case .file:   return scriptFilePath
        }
    }

    /// launchd / 実行時の ProgramArguments
    var programArguments: [String] {
        var args: [String] = []
        let path = resolvedScriptPath
        switch scriptKind {
        case .inline:
            // インラインは必ずインタプリタ経由で実行
            args = [interpreter.isEmpty ? "/bin/zsh" : interpreter, path]
        case .file:
            if interpreter.isEmpty {
                args = [path]
            } else {
                args = [interpreter, path]
            }
        }
        args.append(contentsOf: arguments)
        return args
    }

    /// 環境変数を辞書化（最低限の PATH を補う）
    var environmentDictionary: [String: String] {
        var dict: [String: String] = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        for e in environment where !e.key.trimmingCharacters(in: .whitespaces).isEmpty {
            dict[e.key] = e.value
        }
        return dict
    }

    /// 一覧に出す人間向けのスケジュール説明
    var scheduleSummary: String {
        switch scheduleMode {
        case .cron:
            return String(localized: "schedule.summary.cron", defaultValue: "cron: \(cronExpression)")
        case .launchd:
            switch launchdKind {
            case .interval:
                switch intervalUnit {
                case .seconds: return String(localized: "schedule.summary.interval.seconds", defaultValue: "\(intervalValue)秒ごと")
                case .minutes: return String(localized: "schedule.summary.interval.minutes", defaultValue: "\(intervalValue)分ごと")
                case .hours:   return String(localized: "schedule.summary.interval.hours",   defaultValue: "\(intervalValue)時間ごと")
                case .days:    return String(localized: "schedule.summary.interval.days",    defaultValue: "\(intervalValue)日ごと")
                }
            case .calendar:
                let hm = String(format: "%02d:%02d", calendar.hour, calendar.minute)
                switch calendar.frequency {
                case .hourly:
                    return String(localized: "schedule.summary.hourly", defaultValue: "毎時 \(calendar.minute) 分")
                case .daily:
                    return String(localized: "schedule.summary.daily", defaultValue: "毎日 \(hm)")
                case .weekly:
                    let days = calendar.weekdays.sorted().map { WeekdaySymbols.short($0) }.joined(separator: "・")
                    return String(localized: "schedule.summary.weekly", defaultValue: "毎週 \(days) \(hm)")
                case .monthly:
                    return String(localized: "schedule.summary.monthly", defaultValue: "毎月 \(calendar.day) 日 \(hm)")
                }
            }
        }
    }
}
