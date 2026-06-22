//
//  AutoShell_execerApp.swift
//  AutoShell-execer
//
//  launchd を使って シェルスクリプトを定期実行する、cron の管理版アプリ。
//

import SwiftUI

@main
struct AutoShell_execerApp: App {
    @State private var store = JobStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 920, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("ジョブを再読み込み") {
                    store.load()
                    Task { await store.refreshAllStates() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
