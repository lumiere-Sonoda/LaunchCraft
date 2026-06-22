//
//  TerminalConsole.swift
//  LaunchCraft
//
//  画面下部のターミナル風ログパネルの状態。
//  テスト実行のライブ出力と、保存済みログファイルの読み込みを扱う。
//

import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class TerminalConsole {

    struct Line: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind
        enum Kind { case stdout, stderr, info }
    }

    var lines: [Line] = []
    var isVisible: Bool = false
    var isRunning: Bool = false
    var title: String = String(localized: "コンソール")

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var pendingOut = ""
    @ObservationIgnored private var pendingErr = ""
    @ObservationIgnored private let maxLines = 5000

    // MARK: 表示制御

    func show() { isVisible = true }
    func toggle() { isVisible.toggle() }

    func clear() {
        lines.removeAll()
        pendingOut = ""
        pendingErr = ""
    }

    // MARK: 行の追加

    func appendInfo(_ text: String) {
        lines.append(Line(text: text, kind: .info))
        trim()
    }

    private func appendChunk(_ chunk: String, kind: Line.Kind) {
        if kind == .stdout { pendingOut += chunk } else { pendingErr += chunk }
        flush(kind: kind, final: false)
    }

    private func flush(kind: Line.Kind, final: Bool) {
        if kind == .stdout {
            let parts = pendingOut.components(separatedBy: "\n")
            for line in parts.dropLast() {
                lines.append(Line(text: line, kind: .stdout))
            }
            pendingOut = final ? "" : (parts.last ?? "")
            if final, let last = parts.last, !last.isEmpty {
                lines.append(Line(text: last, kind: .stdout))
            }
        } else {
            let parts = pendingErr.components(separatedBy: "\n")
            for line in parts.dropLast() {
                lines.append(Line(text: line, kind: .stderr))
            }
            pendingErr = final ? "" : (parts.last ?? "")
            if final, let last = parts.last, !last.isEmpty {
                lines.append(Line(text: last, kind: .stderr))
            }
        }
        trim()
    }

    private func trim() {
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    // MARK: テスト実行（ライブ）

    /// 現在編集中のジョブをそのまま実行してライブ表示する。保存・launchd 登録は行わない。
    func runTest(job: ShellJob) {
        stop()
        clear()
        show()
        isRunning = true
        title = String(localized: "console.title.test", defaultValue: "テスト実行: \(job.name)")

        let executable: String
        let arguments: [String]
        var tempURL: URL?

        switch job.scriptKind {
        case .inline:
            // インラインコードを一時ファイルへ書き出して実行
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("launchcraft-test-\(UUID().uuidString).sh")
            do {
                try job.inlineCode.write(to: tmp, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
            } catch {
                appendInfo(String(localized: "console.tmpScriptFailed", defaultValue: "一時スクリプトの作成に失敗: \(error.localizedDescription)"))
                isRunning = false
                return
            }
            tempURL = tmp
            executable = job.interpreter.isEmpty ? "/bin/zsh" : job.interpreter
            arguments = [tmp.path] + job.arguments
        case .file:
            guard !job.scriptFilePath.isEmpty,
                  FileManager.default.fileExists(atPath: job.scriptFilePath) else {
                appendInfo(String(localized: "console.scriptNotFound", defaultValue: "スクリプトファイルが見つかりません: \(job.scriptFilePath)"))
                isRunning = false
                return
            }
            if job.interpreter.isEmpty {
                executable = job.scriptFilePath
                arguments = job.arguments
            } else {
                executable = job.interpreter
                arguments = [job.scriptFilePath] + job.arguments
            }
        }

        appendInfo("$ \(([executable] + arguments).joined(separator: " "))")

        let env = job.environmentDictionary
        let wd = job.workingDirectory
        let (proc, events) = ShellRunner.stream(
            executable: executable,
            arguments: arguments,
            environment: env,
            currentDirectory: wd.isEmpty ? nil : wd
        )
        process = proc

        streamTask = Task { [weak self] in
            for await ev in events {
                guard let self else { break }
                switch ev {
                case .stdout(let s): self.appendChunk(s, kind: .stdout)
                case .stderr(let s): self.appendChunk(s, kind: .stderr)
                case .terminated(let code):
                    self.flush(kind: .stdout, final: true)
                    self.flush(kind: .stderr, final: true)
                    self.appendInfo(String(localized: "console.exitCode", defaultValue: "― 終了コード \(Int(code)) ―"))
                    self.isRunning = false
                }
            }
            if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
        }
    }

    /// 実行中のテストを停止する。
    func stop() {
        streamTask?.cancel()
        streamTask = nil
        if let p = process, p.isRunning {
            p.terminate()
        }
        process = nil
        isRunning = false
    }

    // MARK: 保存済みログの読み込み（今すぐ実行のあとなどに）

    func loadLogs(for job: ShellJob) {
        clear()
        show()
        title = String(localized: "console.title.logs", defaultValue: "ログ: \(job.name)")
        let out = (try? String(contentsOf: job.stdoutLogURL, encoding: .utf8)) ?? ""
        let err = (try? String(contentsOf: job.stderrLogURL, encoding: .utf8)) ?? ""
        if out.isEmpty && err.isEmpty {
            appendInfo(String(localized: "ログはまだありません。"))
            return
        }
        if !out.isEmpty {
            appendInfo(String(localized: "―― 標準出力 (stdout) ――"))
            for line in out.components(separatedBy: "\n") where !line.isEmpty {
                lines.append(Line(text: line, kind: .stdout))
            }
        }
        if !err.isEmpty {
            appendInfo(String(localized: "―― 標準エラー (stderr) ――"))
            for line in err.components(separatedBy: "\n") where !line.isEmpty {
                lines.append(Line(text: line, kind: .stderr))
            }
        }
        trim()
    }

    /// コンソール内容をプレーンテキストとして取り出す（保存用）。
    var plainText: String {
        lines.map { line in
            switch line.kind {
            case .stdout: return line.text
            case .stderr: return "[err] " + line.text
            case .info:   return line.text
            }
        }.joined(separator: "\n")
    }
}
