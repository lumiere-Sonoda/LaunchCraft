//
//  ContentView.swift
//  AutoShell-execer
//
//  メイン画面。左:ジョブ一覧 / 右:編集 / 下:ターミナル風コンソール。
//

import SwiftUI

struct ContentView: View {
    @Environment(JobStore.self) private var store
    @State private var console = TerminalConsole()
    @State private var selection: ShellJob.ID?

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
            } detail: {
                detail
            }

            if console.isVisible {
                Divider()
                TerminalPanelView(console: console)
                    .frame(height: 260)
                    .transition(.move(edge: .bottom))
            }
        }
        .environment(console)
        .animation(.easeInOut(duration: 0.22), value: console.isVisible)
        .task { await store.refreshAllStates() }
        .overlay(alignment: .bottom) { messageBar }
    }

    // MARK: サイドバー

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(store.jobs) { job in
                    JobRow(job: job, state: store.state(for: job))
                        .tag(job.id)
                        .contextMenu {
                            Button(job.enabled ? "無効にする" : "有効にする") {
                                Task { await store.setEnabled(!job.enabled, for: job) }
                            }
                            Button("削除", role: .destructive) {
                                Task { await store.delete(job); if selection == job.id { selection = nil } }
                            }
                        }
                }
            } header: {
                Text("ジョブ (\(store.jobs.count))")
            }
        }
        .navigationTitle(Text(verbatim: "AutoShell"))
        .navigationSplitViewColumnWidth(min: 250, ideal: 290)
        .safeAreaInset(edge: .bottom) {
            Button {
                addJob()
            } label: {
                Label("ジョブを追加", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .toolbar {
            ToolbarItem {
                Button { addJob() } label: { Label("追加", systemImage: "plus") }
                    .help("新しいジョブを追加")
            }
            ToolbarItem {
                Button { Task { await store.refreshAllStates() } } label: {
                    Label("更新", systemImage: "arrow.clockwise")
                }
                .help("状態を更新")
            }
            ToolbarItem {
                Button { console.toggle() } label: {
                    Label("コンソール", systemImage: "terminal")
                }
                .help("コンソールの表示切り替え")
            }
        }
    }

    // MARK: 詳細

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let job = store.jobs.first(where: { $0.id == id }) {
            JobEditorView(job: job, onClose: { selection = nil })
                .id(id)
        } else {
            ContentUnavailableView {
                Label("ジョブが選択されていません", systemImage: "clock.badge")
            } description: {
                Text("左の ＋ から新しいスケジュール実行を作成できます。")
            } actions: {
                Button { addJob() } label: {
                    Label("ジョブを追加", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: メッセージ

    @ViewBuilder
    private var messageBar: some View {
        if !store.lastMessage.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: store.lastMessageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(store.lastMessageIsError ? Color.red : Color.green)
                Text(store.lastMessage)
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .padding(.bottom, console.isVisible ? 272 : 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                Task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    store.lastMessage = ""
                }
            }
        }
    }

    private func addJob() {
        let job = store.addDraft()
        selection = job.id
    }
}

// MARK: - 一覧の1行

struct JobRow: View {
    let job: ShellJob
    let state: JobRuntimeState

    var body: some View {
        HStack(spacing: 11) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(statusColor.opacity(0.35), lineWidth: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(job.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .imageScale(.small)
                    Text(job.scheduleSummary)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if !job.enabled {
                Text("無効")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        if !job.enabled { return .gray }
        switch state {
        case .loaded(let pid): return pid != nil ? .green : .blue
        case .notLoaded:       return Color.gray.opacity(0.5)
        case .unknown:         return .secondary
        }
    }
}
