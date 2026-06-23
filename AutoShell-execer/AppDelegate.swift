//
//  AppDelegate.swift
//  LaunchCraft
//
//  メニューバー常駐アプリとしての挙動を担当する。
//  - 最後のウィンドウを閉じてもアプリは終了せず、メニューバーに常駐する。
//  - 通常ウィンドウが開いている間だけ Dock アイコン＋アプリメニューを表示し（.regular）、
//    閉じている間は Dock から消えてバックグラウンド常駐する（.accessory）。
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        let nc = NotificationCenter.default
        // ウィンドウの開閉に追従して Dock アイコンの表示/非表示を切り替える
        nc.addObserver(self, selector: #selector(windowStateChanged),
                       name: NSWindow.didBecomeKeyNotification, object: nil)
        nc.addObserver(self, selector: #selector(windowStateChanged),
                       name: NSWindow.willCloseNotification, object: nil)
        // 起動直後はまだウィンドウが生成途中のことがある。次のループで判定し、
        // 起動時に一瞬 Dock アイコンが消えるちらつきを防ぐ。
        DispatchQueue.main.async { [weak self] in self?.updateActivationPolicy() }
    }

    /// 最後のウィンドウを閉じてもアプリを終了させない（メニューバーに常駐）。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func windowStateChanged(_ note: Notification) {
        // willClose 時点ではまだウィンドウが可視のため、クローズ完了後に判定する
        DispatchQueue.main.async { [weak self] in
            self?.updateActivationPolicy()
        }
    }

    /// 通常の編集ウィンドウが見えていれば Dock に出し、無ければメニューバーのみにする。
    private func updateActivationPolicy() {
        let hasVisibleWindow = NSApp.windows.contains { isMainWindow($0) }
        let desired: NSApplication.ActivationPolicy = hasVisibleWindow ? .regular : .accessory
        guard NSApp.activationPolicy() != desired else { return }
        NSApp.setActivationPolicy(desired)
        // .regular に戻したときはアプリを前面に出してウィンドウを操作可能にする
        if desired == .regular {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// メニューバーパネル（borderless / 高レベル）を除いた、本来の編集ウィンドウかどうか。
    private func isMainWindow(_ window: NSWindow) -> Bool {
        window.isVisible
            && !(window is NSPanel)
            && window.styleMask.contains(.titled)
            && window.level == .normal
    }
}
