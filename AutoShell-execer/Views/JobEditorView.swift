//
//  JobEditorView.swift
//  LaunchCraft
//
//  選択したジョブの編集フォーム。macOS ネイティブの Form ベース。
//

import SwiftUI
import AppKit

struct JobEditorView: View {
    @Environment(JobStore.self) private var store
    @Environment(TerminalConsole.self) private var console

    /// 選択行が変わるたびに `.id()` で作り直され、@State が初期化される。
    @State private var job: ShellJob
    @State private var showDeleteConfirm = false
    @State private var showLogViewer = false

    let onClose: () -> Void

    private let interpreterPresets = [
        "/bin/zsh", "/bin/bash", "/bin/sh",
        "/usr/bin/python3", "/usr/bin/ruby", "/usr/bin/perl"
    ]

    init(job: ShellJob, onClose: @escaping () -> Void) {
        _job = State(initialValue: job)
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                basicSection
                scriptSection
                scheduleSection
                environmentSection
                optionsSection
                plistPreviewSection
            }
            .formStyle(.grouped)

            Divider()
            actionBar
        }
        .navigationTitle(job.name.isEmpty ? String(localized: "（無名のジョブ）") : job.name)
        .task(id: job.id) {
            await store.refreshRunInfo(for: job)
        }
        .alert("このジョブを削除しますか？", isPresented: $showDeleteConfirm) {
            Button("削除", role: .destructive) {
                Task { await store.delete(job); onClose() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("launchd の登録を解除し、設定とログを削除します。")
        }
        .sheet(isPresented: $showLogViewer) {
            VStack(spacing: 0) {
                HStack {
                    Text("ログ: \(job.name)")
                        .font(.headline)
                    Spacer()
                    Button("閉じる") { showLogViewer = false }
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
                Divider()
                LogViewerView(job: job)
            }
            .frame(minWidth: 720, minHeight: 480)
        }
    }

    // MARK: 基本

    private var basicSection: some View {
        Section {
            TextField("名前", text: $job.name, prompt: Text("ジョブ名"))
            Toggle("このジョブを有効にする", isOn: $job.enabled)
            LabeledContent("ラベル") {
                Text(job.label)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            LabeledContent("最終実行") {
                lastRunView
            }
        } header: {
            sectionHeader("基本", systemImage: "info.circle")
        }
    }

    // MARK: スクリプト

    private var scriptSection: some View {
        Section {
            Picker("方法", selection: $job.scriptKind) {
                ForEach(ScriptKind.allCases) { k in
                    Text(k.label).tag(k)
                }
            }
            .pickerStyle(.segmented)

            interpreterRow

            if job.scriptKind == .inline {
                VStack(alignment: .leading, spacing: 6) {
                    Text("シェルスクリプト / コード")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $job.inlineCode)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 170)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.3)))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            } else {
                LabeledContent("ファイル") {
                    HStack {
                        TextField("スクリプトファイルのパス", text: $job.scriptFilePath,
                                  prompt: Text("スクリプトファイルのパス"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        Button("選択…") { pickScriptFile() }
                    }
                }
            }

            TextField("引数", text: argumentsBinding, prompt: Text("スペース区切り（任意）"))
                .font(.system(.body, design: .monospaced))
        } header: {
            sectionHeader("実行するスクリプト", systemImage: "terminal")
        }
    }

    private var interpreterRow: some View {
        LabeledContent("インタプリタ") {
            HStack(spacing: 6) {
                TextField("インタプリタ", text: $job.interpreter, prompt: Text(verbatim: "/bin/zsh"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: 260)
                Menu {
                    ForEach(interpreterPresets, id: \.self) { p in
                        Button(p) { job.interpreter = p }
                    }
                    if job.scriptKind == .file {
                        Divider()
                        Button("（ファイルを直接実行）") { job.interpreter = "" }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                }
                .menuIndicator(.hidden)
                .buttonStyle(.borderless)
                .fixedSize()
            }
        }
    }

    // MARK: スケジュール

    private var scheduleSection: some View {
        Section {
            ScheduleEditorView(job: $job)
        } header: {
            sectionHeader("スケジュール", systemImage: "calendar")
        }
    }

    // MARK: 作業ディレクトリ・環境変数

    private var environmentSection: some View {
        Section {
            LabeledContent("作業フォルダ") {
                HStack {
                    TextField("作業フォルダ", text: $job.workingDirectory, prompt: Text("（任意）"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button("選択…") { pickWorkingDir() }
                }
            }

            ForEach($job.environment) { $env in
                HStack(spacing: 6) {
                    TextField("KEY", text: $env.key, prompt: Text("KEY"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 170)
                    Text(verbatim: "=").foregroundStyle(.secondary)
                    TextField("値", text: $env.value, prompt: Text("値"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button {
                        job.environment.removeAll { $0.id == env.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }

            Button {
                job.environment.append(EnvVar())
            } label: {
                Label("環境変数を追加", systemImage: "plus.circle")
            }

            if job.environment.isEmpty {
                Text("PATH は自動で補われます。追加したい変数があればここで指定します。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("作業ディレクトリ・環境変数", systemImage: "folder")
        }
    }

    // MARK: オプション

    private var optionsSection: some View {
        Section {
            Toggle("ログイン時にも一度実行する (RunAtLoad)", isOn: $job.runAtLoad)
            Toggle("常駐させ、終了したら自動再起動する (KeepAlive)", isOn: $job.keepAlive)
            if job.keepAlive {
                Label("KeepAlive はスケジュールよりも「動き続ける」挙動が優先されます。常駐プロセス向けです。", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("オプション", systemImage: "gearshape")
        }
    }

    // MARK: plist プレビュー

    private var plistPreviewSection: some View {
        Section {
            DisclosureGroup("生成される launchd plist を確認") {
                ScrollView(.horizontal) {
                    Text(LaunchAgent.plistXMLString(for: job))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.vertical, 6)
                }
                .frame(maxHeight: 220)
            }
        }
    }

    // MARK: アクションバー

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                console.runTest(job: job)
            } label: {
                Label("テスト実行", systemImage: "play.circle")
            }
            .help("保存せずに今のスクリプトをそのまま実行し、下のコンソールに出力します")

            Button {
                Task {
                    _ = await store.runNow(job)
                    // 少し待ってからログを表示
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    console.loadLogs(for: job)
                }
            } label: {
                Label("今すぐ実行", systemImage: "bolt.circle")
            }
            .help("登録済みジョブを launchd 経由で即実行し、ログを表示します")

            Button {
                showLogViewer = true
            } label: {
                Label("ログを見る", systemImage: "doc.text")
            }

            Spacer()

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("削除", systemImage: "trash")
            }

            Button {
                Task { await store.saveAndSync(job) }
            } label: {
                Label("保存して登録", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: ヘルパー

    @ViewBuilder
    private var lastRunView: some View {
        if let info = store.runInfo(for: job) {
            HStack(spacing: 10) {
                if let date = info.lastRunAt {
                    Text(DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("未実行")
                        .foregroundStyle(.tertiary)
                }
                if let code = info.lastExitCode {
                    Label(
                        code == 0
                            ? String(localized: "exitCode.success", defaultValue: "成功")
                            : String(localized: "exitCode.failure", defaultValue: "コード \(code)"),
                        systemImage: code == 0 ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(code == 0 ? Color.green : Color.orange)
                    .font(.caption)
                }
            }
        } else {
            Text("—")
                .foregroundStyle(.tertiary)
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
            .textCase(nil)
    }

    private var argumentsBinding: Binding<String> {
        Binding(
            get: { job.arguments.joined(separator: " ") },
            set: { job.arguments = $0.split(separator: " ").map(String.init) }
        )
    }

    private func pickScriptFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            job.scriptFilePath = url.path
        }
    }

    private func pickWorkingDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            job.workingDirectory = url.path
        }
    }
}
