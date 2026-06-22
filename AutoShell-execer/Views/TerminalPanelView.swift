//
//  TerminalPanelView.swift
//  LaunchCraft
//
//  画面下部にせり出すターミナル風ログパネル。
//

import SwiftUI
import AppKit

struct TerminalPanelView: View {
    @Bindable var console: TerminalConsole

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logBody
        }
        .background(Color(red: 0.07, green: 0.08, blue: 0.10))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .foregroundStyle(.green)
            Text(console.title)
                .font(.system(.subheadline, design: .monospaced)).bold()
                .foregroundStyle(Color(white: 0.9))
            if console.isRunning {
                ProgressView().controlSize(.small)
                Button("停止") { console.stop() }
                    .controlSize(.small)
            }
            Spacer()
            Button { saveLog() } label: {
                Label("保存", systemImage: "square.and.arrow.down")
            }
            .controlSize(.small)
            .disabled(console.lines.isEmpty)
            Button { console.clear() } label: {
                Label("クリア", systemImage: "trash")
            }
            .controlSize(.small)
            .disabled(console.lines.isEmpty)
            Button { console.isVisible = false } label: {
                Image(systemName: "chevron.down")
            }
            .controlSize(.small)
            .help("コンソールを閉じる")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.12, green: 0.13, blue: 0.16))
    }

    private var logBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(console.lines) { line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(color(for: line.kind))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .onChange(of: console.lines.count) { _, _ in
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func color(for kind: TerminalConsole.Line.Kind) -> Color {
        switch kind {
        case .stdout: return Color(white: 0.92)
        case .stderr: return Color(red: 1.0, green: 0.45, blue: 0.45)
        case .info:   return Color(red: 0.55, green: 0.75, blue: 1.0)
        }
    }

    private func saveLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "launchcraft-log.txt"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? console.plainText.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
