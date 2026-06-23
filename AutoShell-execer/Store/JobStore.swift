//
//  JobStore.swift
//  LaunchCraft
//
//  ジョブ一覧の管理。JSON の読み書きと launchd への反映を仲介する。
//

import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class JobStore {
    var jobs: [ShellJob] = []
    var states: [UUID: JobRuntimeState] = [:]
    var runInfos: [UUID: JobRunInfo] = [:]
    var lastMessage: String = ""
    var lastMessageIsError: Bool = false

    @ObservationIgnored
    private var clearMessageTask: Task<Void, Never>?

    @ObservationIgnored
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    @ObservationIgnored
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        Paths.ensureDirectories()
        load()
    }

    // MARK: 読み込み・保存

    func load() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: Paths.jobsDir, includingPropertiesForKeys: nil
        ) else {
            jobs = []
            return
        }
        var loaded: [ShellJob] = []
        for url in urls where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let job = try? decoder.decode(ShellJob.self, from: data) {
                loaded.append(job)
            }
        }
        jobs = loaded.sorted { $0.createdAt < $1.createdAt }
    }

    private func persist(_ job: ShellJob) throws {
        Paths.ensureDirectories()
        let data = try encoder.encode(job)
        try data.write(to: job.metadataURL, options: .atomic)
    }

    // MARK: ジョブ操作

    /// 新規ジョブを作成して配列へ追加（まだ launchd には反映しない）。
    func addDraft() -> ShellJob {
        var job = ShellJob()
        job.name = String(localized: "新しいジョブ")
        jobs.append(job)
        try? persist(job)
        return job
    }

    /// 編集内容を保存し、launchd に反映する。
    func saveAndSync(_ job: ShellJob) async {
        var updated = job
        updated.lastModified = Date()

        // 配列を更新
        if let idx = jobs.firstIndex(where: { $0.id == updated.id }) {
            jobs[idx] = updated
        } else {
            jobs.append(updated)
        }

        do {
            try persist(updated)
        } catch {
            report(String(localized: "msg.saveFailed", defaultValue: "保存に失敗: \(error.localizedDescription)"), isError: true)
            return
        }

        let outcome = await LaunchctlService.sync(job: updated)
        report(outcome.detail, isError: !outcome.success)
        await refreshState(for: updated)
        await refreshRunInfo(for: updated)
    }

    /// 有効/無効を切り替えて反映する。
    func setEnabled(_ enabled: Bool, for job: ShellJob) async {
        guard let idx = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[idx].enabled = enabled
        let updated = jobs[idx]
        try? persist(updated)
        let outcome = await LaunchctlService.sync(job: updated)
        report(outcome.detail, isError: !outcome.success)
        await refreshState(for: updated)
    }

    /// 今すぐ実行。実行後にログを読みたい場合は呼び出し側でログ URL を参照する。
    func runNow(_ job: ShellJob) async -> LaunchctlOutcome {
        // 無効ジョブは launchd に登録されていない（kickstart が失敗する）ため、
        // launchd を介さず直接実行する。enabled の状態は変えない。
        if !job.enabled {
            let outcome = await runDirect(job)
            report(outcome.detail, isError: !outcome.success)
            await refreshRunInfo(for: job)
            return outcome
        }

        // 有効ジョブ: 未読込なら一度反映してから kickstart する。
        let state = await LaunchctlService.state(label: job.label)
        if state == .notLoaded {
            _ = await LaunchctlService.sync(job: job)
        }
        let outcome = await LaunchctlService.kickstart(label: job.label, restart: true)
        report(outcome.detail, isError: !outcome.success)
        await refreshState(for: job)
        // 少し待ってからログ更新日時を取得（launchd がファイルを書き終わるのを待つ）
        try? await Task.sleep(nanoseconds: 800_000_000)
        await refreshRunInfo(for: job)
        return outcome
    }

    /// 無効ジョブ用の直接実行。launchd を介さずスクリプトを実行し、出力をログへ追記する。
    private func runDirect(_ job: ShellJob) async -> LaunchctlOutcome {
        // インラインスクリプトを最新化（file モードでは何もしない）
        try? LaunchAgent.writeInlineScript(for: job)

        if job.scriptKind == .file,
           job.scriptFilePath.isEmpty || !FileManager.default.fileExists(atPath: job.scriptFilePath) {
            return LaunchctlOutcome(success: false, detail: String(localized: "run.scriptNotFound", defaultValue: "スクリプトファイルが見つかりません"))
        }

        let args = job.programArguments
        guard let exe = args.first else {
            return LaunchctlOutcome(success: false, detail: String(localized: "run.noCommand", defaultValue: "実行するコマンドがありません"))
        }
        let wd = job.workingDirectory
        let result = await ShellRunner.runCapture(
            executable: exe,
            arguments: Array(args.dropFirst()),
            environment: job.environmentDictionary,
            currentDirectory: wd.isEmpty ? nil : wd
        )

        // launchd と同じようにログファイルへ追記する（「ログを見る」「最終実行」で参照できる）。
        appendToLog(result.stdout, at: job.stdoutLogURL)
        appendToLog(result.stderr, at: job.stderrLogURL)

        if result.status == 0 {
            return LaunchctlOutcome(success: true, detail: String(localized: "run.directSuccess", defaultValue: "実行しました（無効ジョブを直接実行）"))
        }
        let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = err.isEmpty
            ? String(localized: "run.directFailed", defaultValue: "終了コード \(Int(result.status))")
            : err
        return LaunchctlOutcome(success: false, detail: detail)
    }

    /// テキストをログファイルへ追記する（無ければ作成）。
    private func appendToLog(_ text: String, at url: URL) {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return }
        Paths.ensureDirectories()
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// ジョブを削除する。
    func delete(_ job: ShellJob) async {
        _ = await LaunchctlService.remove(job: job)
        let fm = FileManager.default
        try? fm.removeItem(at: job.metadataURL)
        if job.scriptKind == .inline {
            try? fm.removeItem(at: job.inlineScriptURL)
        }
        try? fm.removeItem(at: job.stdoutLogURL)
        try? fm.removeItem(at: job.stderrLogURL)
        jobs.removeAll { $0.id == job.id }
        states[job.id] = nil
        report(String(localized: "msg.deleted", defaultValue: "「\(job.name)」を削除しました"), isError: false)
    }

    // MARK: 状態

    func refreshState(for job: ShellJob) async {
        let s = await LaunchctlService.state(label: job.label)
        states[job.id] = s
    }

    func refreshAllStates() async {
        for job in jobs {
            states[job.id] = await LaunchctlService.state(label: job.label)
        }
    }

    func state(for job: ShellJob) -> JobRuntimeState {
        states[job.id] ?? .unknown
    }

    // MARK: 実行履歴

    func refreshRunInfo(for job: ShellJob) async {
        runInfos[job.id] = await LaunchctlService.runInfo(for: job)
    }

    func runInfo(for job: ShellJob) -> JobRunInfo? {
        runInfos[job.id]
    }

    // MARK: Import / Export

    /// 全ジョブを JSON バンドルとしてエンコードする。
    func bundleData() throws -> Data {
        let bundle = JobBundle(jobs: jobs)
        return try encoder.encode(bundle)
    }

    /// JSON バンドルを読み込み、ジョブを追加・launchd へ登録する。
    func importBundle(from data: Data) async {
        guard let bundle = try? decoder.decode(JobBundle.self, from: data) else {
            report(String(localized: "import.failed", defaultValue: "読み込みに失敗しました（形式が不正です）"), isError: true)
            return
        }
        var imported = 0
        for var job in bundle.jobs {
            // UUID を振り直してコリジョンを防ぐ
            job.id = UUID()
            job.createdAt = Date()
            job.lastModified = Date()
            do {
                try persist(job)
                jobs.append(job)
                _ = await LaunchctlService.sync(job: job)
                imported += 1
            } catch {
                jobs.removeAll { $0.id == job.id }
            }
        }
        if imported > 0 {
            report(String(localized: "import.success", defaultValue: "\(imported) 件のジョブを読み込みました"), isError: false)
        } else {
            report(String(localized: "import.failed", defaultValue: "読み込みに失敗しました（形式が不正です）"), isError: true)
        }
    }

    // MARK: メッセージ

    func report(_ message: String, isError: Bool) {
        lastMessage = message
        lastMessageIsError = isError

        // メインウィンドウが閉じている（メニューバー常駐）場合でもメッセージが
        // 残り続けないよう、ストア側で 4 秒後に自動でクリアする。
        clearMessageTask?.cancel()
        guard !message.isEmpty else { return }
        clearMessageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.lastMessage = ""
        }
    }
}
