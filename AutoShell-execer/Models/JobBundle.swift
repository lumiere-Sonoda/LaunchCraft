//
//  JobBundle.swift
//  LaunchCraft
//
//  ジョブ設定の書き出し・読み込みに使うコンテナ。
//  version フィールドで将来のフォーマット変更に対応できるようにする。
//

import Foundation

struct JobBundle: Codable {
    var version: Int = 1
    var exportedAt: Date = Date()
    var jobs: [ShellJob]
}
