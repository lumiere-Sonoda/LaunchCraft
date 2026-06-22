//
//  LaunchCraftApp.swift
//  LaunchCraft
//
//  launchd を使ってシェルスクリプトを定期実行する、cron の GUI 管理アプリ。
//

import SwiftUI

@main
struct LaunchCraftApp: App {
    @State private var store = JobStore()

    var body: some Scene {
        WindowGroup(id: "main") {
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

        MenuBarExtra("LaunchCraft", systemImage: "clock.arrow.circlepath") {
            MenuBarMenuView()
                .environment(store)
        }
        .menuBarExtraStyle(.window)
    }
}
