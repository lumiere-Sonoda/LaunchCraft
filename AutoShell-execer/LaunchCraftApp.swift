//
//  LaunchCraftApp.swift
//  LaunchCraft
//
//  launchd を使ってシェルスクリプトを定期実行する、cron の GUI 管理アプリ。
//

import SwiftUI

@main
struct LaunchCraftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = JobStore()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(store)
                .environment(settings)
                .frame(minWidth: 920, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("設定…") {
                    settings.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
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
                .environment(settings)
        }
        .menuBarExtraStyle(.window)
    }
}
