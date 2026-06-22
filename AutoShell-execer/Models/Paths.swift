//
//  Paths.swift
//  AutoShell-execer
//
//  アプリが使うディレクトリ・ファイルパスを一元管理する。
//

import Foundation

enum Paths {
    /// 例: ~/Library/Application Support/AutoShell-execer
    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("LaunchCraft", isDirectory: true)
    }

    /// ジョブのメタデータ(JSON)を保存する場所（このアプリの真実の源）
    static var jobsDir: URL { appSupport.appendingPathComponent("jobs", isDirectory: true) }

    /// インラインスクリプトの .sh を保存する場所
    static var scriptsDir: URL { appSupport.appendingPathComponent("scripts", isDirectory: true) }

    /// 標準出力・標準エラーのログ保存場所
    static var logsDir: URL { appSupport.appendingPathComponent("logs", isDirectory: true) }

    /// launchd のユーザーエージェント置き場 ~/Library/LaunchAgents
    static var launchAgentsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    /// 必要なディレクトリを全て作成する。
    static func ensureDirectories() {
        for dir in [appSupport, jobsDir, scriptsDir, logsDir, launchAgentsDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
