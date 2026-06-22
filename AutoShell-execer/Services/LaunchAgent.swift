//
//  LaunchAgent.swift
//  LaunchCraft
//
//  ShellJob から launchd の plist 辞書を組み立て、ファイルへ書き出す/削除する。
//

import Foundation

enum LaunchAgentError: LocalizedError {
    case scheduleBuildFailed(String)
    var errorDescription: String? {
        switch self {
        case .scheduleBuildFailed(let m): return m
        }
    }
}

enum LaunchAgent {

    /// ShellJob から launchd plist の辞書を作る。
    static func plistDictionary(for job: ShellJob) throws -> [String: Any] {
        var dict: [String: Any] = [
            "Label": job.label,
            "ProgramArguments": job.programArguments,
            "StandardOutPath": job.stdoutLogURL.path,
            "StandardErrorPath": job.stderrLogURL.path,
            "EnvironmentVariables": job.environmentDictionary,
            "ProcessType": "Background"
        ]

        let wd = job.workingDirectory.trimmingCharacters(in: .whitespaces)
        if !wd.isEmpty {
            dict["WorkingDirectory"] = wd
        }

        if job.runAtLoad {
            dict["RunAtLoad"] = true
        }
        if job.keepAlive {
            dict["KeepAlive"] = true
        }

        // スケジュール
        switch job.scheduleMode {
        case .launchd:
            switch job.launchdKind {
            case .interval:
                let seconds = max(1, job.intervalValue) * job.intervalUnit.multiplier
                dict["StartInterval"] = seconds
            case .calendar:
                let entries = CronTranslator.calendarSchedule(from: job.calendar)
                dict["StartCalendarInterval"] = entries.count == 1 ? entries[0] : entries
            }
        case .cron:
            let schedule: LaunchdSchedule
            do {
                schedule = try CronTranslator.toLaunchd(job.cronExpression)
            } catch {
                throw LaunchAgentError.scheduleBuildFailed(error.localizedDescription)
            }
            switch schedule {
            case .interval(let secs):
                dict["StartInterval"] = secs
            case .calendar(let entries):
                dict["StartCalendarInterval"] = entries.count == 1 ? entries[0] : entries
            }
        }

        // KeepAlive と RunAtLoad の両方が無い純粋な間隔/カレンダージョブでも問題なし。
        return dict
    }

    /// plist の XML データを生成する。
    static func plistData(for job: ShellJob) throws -> Data {
        let dict = try plistDictionary(for: job)
        return try PropertyListSerialization.data(
            fromPropertyList: dict, format: .xml, options: 0
        )
    }

    /// plist の XML 文字列（プレビュー用）。
    static func plistXMLString(for job: ShellJob) -> String {
        do {
            let data = try plistData(for: job)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "// plist を生成できません: \(error.localizedDescription)"
        }
    }

    /// plist を LaunchAgents へ書き出す。
    static func writePlist(for job: ShellJob) throws {
        Paths.ensureDirectories()
        let data = try plistData(for: job)
        try data.write(to: job.plistURL, options: .atomic)
    }

    /// plist を削除する。
    static func removePlist(for job: ShellJob) {
        try? FileManager.default.removeItem(at: job.plistURL)
    }

    /// インラインスクリプトを .sh として書き出し、実行権限を付ける。
    static func writeInlineScript(for job: ShellJob) throws {
        guard job.scriptKind == .inline else { return }
        Paths.ensureDirectories()
        try job.inlineCode.write(to: job.inlineScriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: job.inlineScriptURL.path
        )
    }
}
