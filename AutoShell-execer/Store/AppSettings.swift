//
//  AppSettings.swift
//  LaunchCraft
//

import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    var menuBarJobCount: Int {
        didSet {
            UserDefaults.standard.set(menuBarJobCount, forKey: "appSettings.menuBarJobCount")
        }
    }

    // 設定シートの表示フラグ（Cmd+, で開く）
    var showSettings: Bool = false

    init() {
        let stored = UserDefaults.standard.integer(forKey: "appSettings.menuBarJobCount")
        menuBarJobCount = stored >= 3 ? stored : 6
    }
}
