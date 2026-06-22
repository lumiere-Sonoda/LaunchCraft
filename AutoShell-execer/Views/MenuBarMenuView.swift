//
//  MenuBarMenuView.swift
//  LaunchCraft
//
//  メニューバー常駐パネル。
//  - store.jobs / store.states は body の先頭で参照し、@Observable の観測トラッキングを確実に登録する。
//  - TimelineView で 30 秒ごとに「次回実行まで」ラベルを再描画する。
//  - ウィンドウを開く際は NSApp で既存ウィンドウを探し、無ければ openWindow で新規作成する。
//

import SwiftUI
import AppKit

// MARK: - メインパネル

struct MenuBarMenuView: View {
    @Environment(JobStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // body の先頭で参照することで @Observable の変更通知を確実に受け取る
        let jobs   = store.jobs
        let states = store.states

        VStack(alignment: .leading, spacing: 0) {
            menuHeader
            Divider()
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                jobListView(jobs: jobs, states: states)
            }
            Divider()
            menuFooter
        }
        .frame(width: 300)
        .task { await store.refreshAllStates() }
    }

    // MARK: ヘッダー

    private var menuHeader: some View {
        HStack(spacing: 8) {
            Text("LaunchCraft")
                .font(.headline)
            Spacer()
            Button("開く") { openMainWindow() }
                .font(.callout)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: ジョブ一覧

    @ViewBuilder
    private func jobListView(jobs: [ShellJob], states: [UUID: JobRuntimeState]) -> some View {
        if jobs.isEmpty {
            Text("ジョブがありません")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 28)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                        if index > 0 {
                            Divider().padding(.leading, 32)
                        }
                        MenuBarJobRow(job: job, state: states[job.id] ?? .unknown)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
    }

    // MARK: フッター

    private var menuFooter: some View {
        HStack(spacing: 6) {
            Button {
                openMainWindow()
            } label: {
                Label("新しいジョブ", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)

            Spacer()

            Button {
                Task { await store.refreshAllStates() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("すべてのジョブの状態を更新")

            Divider().frame(height: 14)

            Button("終了") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: ウィンドウを開く

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // WindowGroup の openWindow(id:) は毎回新規ウィンドウを作るため、
        // 既存タイトルバー付きウィンドウを直接探して前面に出す。
        if let w = NSApp.windows.first(where: {
            !($0 is NSPanel) && $0.styleMask.contains(.titled)
        }) {
            w.makeKeyAndOrderFront(nil)
        } else {
            // ウィンドウが閉じられていた場合のみ新規作成
            openWindow(id: "main")
        }
    }
}

// MARK: - ジョブ行

struct MenuBarJobRow: View {
    let job: ShellJob
    let state: JobRuntimeState

    @Environment(JobStore.self) private var store
    @State private var isRunning = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // 状態インジケータ
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(statusColor.opacity(0.3), lineWidth: 3))

            // ジョブ名 + 次回実行時刻
            VStack(alignment: .leading, spacing: 2) {
                Text(job.name)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if job.enabled, let label = NextRunCalculator.nextRunLabel(for: job) {
                    Text("次回: \(label)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if !job.enabled {
                    Text("無効")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 4)

            // 今すぐ実行
            Button {
                guard !isRunning else { return }
                isRunning = true
                Task {
                    _ = await store.runNow(job)
                    isRunning = false
                }
            } label: {
                Image(systemName: isRunning ? "ellipsis" : "play.fill")
                    .imageScale(.small)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isRunning ? Color.secondary : Color.accentColor)
            .help("今すぐ実行")

            // 有効/無効トグル
            Button {
                Task { await store.setEnabled(!job.enabled, for: job) }
            } label: {
                Image(systemName: job.enabled ? "checkmark.circle.fill" : "circle")
                    .imageScale(.medium)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(job.enabled ? Color.green : Color.gray)
            .help(job.enabled ? "無効にする" : "有効にする")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        if !job.enabled { return .gray }
        switch state {
        case .loaded(let pid): return pid != nil ? .green : .blue
        case .notLoaded:       return .gray.opacity(0.5)
        case .unknown:         return .secondary
        }
    }
}
