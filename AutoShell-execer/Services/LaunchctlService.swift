//
//  LaunchctlService.swift
//  LaunchCraft
//
//  launchctl コマンドの薄いラッパー。modern な bootstrap/bootout/enable/disable/kickstart を使う。
//  ドメインターゲットは gui/<uid>。
//

import Foundation

nonisolated struct LaunchctlOutcome: Sendable {
    let success: Bool
    let detail: String
}

/// ジョブの実行履歴（launchctl print + ログファイル更新日時から取得）
nonisolated struct JobRunInfo: Sendable {
    let lastExitCode: Int?
    let lastRunAt: Date?
}

/// launchd 上のジョブの状態
nonisolated enum JobRuntimeState: Sendable, Equatable {
    case notLoaded            // bootstrap されていない
    case loaded(pid: Int?)    // 読み込まれている（pid があれば実行中）
    case unknown

    var label: String {
        switch self {
        case .notLoaded:        return String(localized: "status.stopped", defaultValue: "停止")
        case .loaded(let pid):  return pid != nil ? String(localized: "status.running", defaultValue: "実行中")
                                                  : String(localized: "status.idle", defaultValue: "待機中")
        case .unknown:          return "—"
        }
    }
}

enum LaunchctlService {

    static let launchctl = "/bin/launchctl"

    nonisolated static var uid: Int { Int(getuid()) }
    nonisolated static var guiDomain: String { "gui/\(getuid())" }

    nonisolated static func serviceTarget(_ label: String) -> String {
        "\(guiDomain)/\(label)"
    }

    // MARK: 基本操作

    /// plist を読み込む（bootstrap）。
    nonisolated static func bootstrap(plistPath: String) async -> LaunchctlOutcome {
        let r = await ShellRunner.runCapture(
            executable: launchctl, arguments: ["bootstrap", guiDomain, plistPath]
        )
        return outcome(r, okMessage: String(localized: "読み込みました"))
    }

    /// ジョブを取り外す（bootout）。
    nonisolated static func bootout(label: String) async -> LaunchctlOutcome {
        let r = await ShellRunner.runCapture(
            executable: launchctl, arguments: ["bootout", serviceTarget(label)]
        )
        return outcome(r, okMessage: String(localized: "取り外しました"))
    }

    /// 永続的に有効化する。
    nonisolated static func enable(label: String) async -> LaunchctlOutcome {
        let r = await ShellRunner.runCapture(
            executable: launchctl, arguments: ["enable", serviceTarget(label)]
        )
        return outcome(r, okMessage: String(localized: "有効化しました"))
    }

    /// 永続的に無効化する。
    nonisolated static func disable(label: String) async -> LaunchctlOutcome {
        let r = await ShellRunner.runCapture(
            executable: launchctl, arguments: ["disable", serviceTarget(label)]
        )
        return outcome(r, okMessage: String(localized: "無効化しました"))
    }

    /// 今すぐ実行する（kickstart）。-k を付けると実行中でも再起動。
    nonisolated static func kickstart(label: String, restart: Bool = false) async -> LaunchctlOutcome {
        var args = ["kickstart"]
        if restart { args.append("-k") }
        args.append(serviceTarget(label))
        let r = await ShellRunner.runCapture(executable: launchctl, arguments: args)
        return outcome(r, okMessage: String(localized: "実行を開始しました"))
    }

    /// ジョブの実行履歴を取得する。
    /// - lastExitCode: launchctl print の "last exit code" フィールド
    /// - lastRunAt: stdout ログファイルの更新日時（ジョブが実行されると launchd が書き込む）
    nonisolated static func runInfo(for job: ShellJob) async -> JobRunInfo {
        let r = await ShellRunner.runCapture(
            executable: launchctl, arguments: ["print", serviceTarget(job.label)]
        )

        var exitCode: Int? = nil
        if r.status == 0 {
            // macOS バージョンにより "last exit code" / "exit status" どちらかが出る
            for pattern in [#"last exit code = (-?\d+)"#, #"exit status = (-?\d+)"#] {
                if let range = r.stdout.range(of: pattern, options: .regularExpression),
                   let eqRange = r.stdout[range].range(of: "= ") {
                    exitCode = Int(String(r.stdout[range][eqRange.upperBound...]))
                    break
                }
            }
        }

        var lastRunAt: Date? = nil
        let logPath = job.stdoutLogURL.path
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
           let size = attrs[.size] as? Int64, size > 0,
           let modDate = attrs[.modificationDate] as? Date {
            lastRunAt = modDate
        }

        return JobRunInfo(lastExitCode: exitCode, lastRunAt: lastRunAt)
    }

    /// 現在の状態を取得する（launchctl print）。
    nonisolated static func state(label: String) async -> JobRuntimeState {
        let r = await ShellRunner.runCapture(
            executable: launchctl, arguments: ["print", serviceTarget(label)]
        )
        if r.status != 0 {
            return .notLoaded
        }
        // "pid = 1234" を探す
        if let range = r.stdout.range(of: #"pid = (\d+)"#, options: .regularExpression) {
            let match = String(r.stdout[range])
            let digits = match.filter { $0.isNumber }
            return .loaded(pid: Int(digits))
        }
        return .loaded(pid: nil)
    }

    /// すべての対象ラベルの状態を 1 回の `launchctl list` でまとめて取得する。
    /// ジョブごとに `print`（重い）を呼ぶより圧倒的に速い（プロセス起動も解析も 1 回）。
    /// 取得に失敗したら空辞書を返し、呼び出し側で既存表示を維持できるようにする。
    nonisolated static func listStates(labels: [String]) async -> [String: JobRuntimeState] {
        let r = await ShellRunner.runCapture(executable: launchctl, arguments: ["list"])
        guard r.status == 0 else { return [:] }

        // 出力は "PID\tStatus\tLabel" のタブ区切り（1 行目はヘッダ）。
        // PID が数値なら実行中、"-" なら読み込み済みで停止中。
        let wanted = Set(labels)
        var result: [String: JobRuntimeState] = [:]
        for line in r.stdout.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }
            let label = cols[2].trimmingCharacters(in: .whitespaces)
            guard wanted.contains(label) else { continue }
            if let pid = Int(cols[0].trimmingCharacters(in: .whitespaces)) {
                result[label] = .loaded(pid: pid)
            } else {
                result[label] = .loaded(pid: nil)
            }
        }
        // list に出てこなかった対象は未読込
        for label in labels where result[label] == nil {
            result[label] = .notLoaded
        }
        return result
    }

    // MARK: 高レベル操作

    /// ジョブを launchd に反映する（plist 書き出し → 既存を bootout → enable/disable → 必要なら bootstrap）。
    nonisolated static func sync(job: ShellJob) async -> LaunchctlOutcome {
        // 既存を一度取り外す（無ければ無視）
        _ = await bootout(label: job.label)

        do {
            try LaunchAgent.writeInlineScript(for: job)
            try LaunchAgent.writePlist(for: job)
        } catch {
            return LaunchctlOutcome(success: false, detail: String(localized: "plistWriteFailed", defaultValue: "plist の書き出しに失敗: \(error.localizedDescription)"))
        }

        if job.enabled {
            _ = await enable(label: job.label)
            let b = await bootstrap(plistPath: job.plistURL.path)
            return b
        } else {
            let d = await disable(label: job.label)
            return d
        }
    }

    /// ジョブを完全に削除する（bootout → disable 解除 → plist 削除）。
    nonisolated static func remove(job: ShellJob) async -> LaunchctlOutcome {
        _ = await bootout(label: job.label)
        // disable のオーバーライドが残らないよう enable に戻しておく
        _ = await enable(label: job.label)
        LaunchAgent.removePlist(for: job)
        return LaunchctlOutcome(success: true, detail: String(localized: "削除しました"))
    }

    // MARK: 補助

    private nonisolated static func outcome(_ r: CommandResult, okMessage: String) -> LaunchctlOutcome {
        if r.status == 0 {
            return LaunchctlOutcome(success: true, detail: okMessage)
        }
        let err = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let out = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = !err.isEmpty ? err : (!out.isEmpty ? out : String(localized: "exitCode", defaultValue: "終了コード \(Int(r.status))"))
        return LaunchctlOutcome(success: false, detail: detail)
    }
}
