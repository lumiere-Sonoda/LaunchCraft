//
//  LogViewerView.swift
//  AutoShell-execer
//
//  stdout / stderr ログファイルをタブ切り替えで表示する専用ビューア。
//  行番号・ファイルサイズ表示、自動更新（2秒ポーリング）、ログ消去に対応。
//

import SwiftUI

struct LogViewerView: View {

    let job: ShellJob

    @State private var selectedTab: LogTab = .stdout
    @State private var stdoutContent = ""
    @State private var stderrContent = ""
    @State private var autoRefresh = false

    enum LogTab: String, CaseIterable, Identifiable {
        case stdout, stderr
        var id: String { rawValue }
        var label: String {
            switch self {
            case .stdout: return String(localized: "標準出力 (stdout)")
            case .stderr: return String(localized: "標準エラー (stderr)")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logArea
            Divider()
            footer
        }
        .onAppear { loadLogs() }
        .task(id: autoRefresh) {
            guard autoRefresh else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                loadLogs()
            }
        }
    }

    // MARK: ツールバー

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $selectedTab) {
                ForEach(LogTab.allCases) { tab in
                    HStack {
                        Text(tab.label)
                        if badgeCount(for: tab) > 0 {
                            Text("\(badgeCount(for: tab))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }.tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            Spacer()

            Toggle("自動更新", isOn: $autoRefresh)
                .toggleStyle(.checkbox)

            Button { loadLogs() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("再読み込み")

            Button { clearCurrentLog() } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("このログを消去")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: ログ表示

    @ViewBuilder
    private var logArea: some View {
        let lines = currentLines
        if lines.isEmpty {
            ContentUnavailableView {
                Label("ログはまだありません", systemImage: "doc.text")
            } description: {
                Text("ジョブを「今すぐ実行」するか、スケジュールで実行されると表示されます。")
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            HStack(alignment: .top, spacing: 0) {
                                Text("\(i + 1)")
                                    .frame(width: 48, alignment: .trailing)
                                    .foregroundStyle(.quaternary)
                                    .padding(.trailing, 6)
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(width: 1)
                                    .padding(.horizontal, 4)
                                Text(line.isEmpty ? " " : line)
                                    .foregroundStyle(
                                        selectedTab == .stderr
                                        ? Color.red.opacity(0.85)
                                        : Color.primary
                                    )
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .padding(.vertical, 1)
                            .id(i)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: lines.count) { _, count in
                    if autoRefresh, let last = lines.indices.last {
                        withAnimation { proxy.scrollTo(last) }
                    }
                }
            }
        }
    }

    // MARK: フッター

    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(currentLines.count) 行")
                .font(.caption)
                .foregroundStyle(.secondary)

            let size = currentFileSize
            if size > 0 {
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(currentLogURL.path)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: ヘルパー

    private var currentLines: [String] {
        let text = selectedTab == .stdout ? stdoutContent : stderrContent
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    private var currentLogURL: URL {
        selectedTab == .stdout ? job.stdoutLogURL : job.stderrLogURL
    }

    private var currentFileSize: Int64 {
        (try? FileManager.default.attributesOfItem(atPath: currentLogURL.path)[.size] as? Int64) ?? 0
    }

    private func badgeCount(for tab: LogTab) -> Int {
        let text = tab == .stdout ? stdoutContent : stderrContent
        guard !text.isEmpty else { return 0 }
        return text.components(separatedBy: "\n").filter { !$0.isEmpty }.count
    }

    private func loadLogs() {
        stdoutContent = (try? String(contentsOf: job.stdoutLogURL, encoding: .utf8)) ?? ""
        stderrContent = (try? String(contentsOf: job.stderrLogURL, encoding: .utf8)) ?? ""
    }

    private func clearCurrentLog() {
        try? "".write(to: currentLogURL, atomically: true, encoding: .utf8)
        loadLogs()
    }
}
