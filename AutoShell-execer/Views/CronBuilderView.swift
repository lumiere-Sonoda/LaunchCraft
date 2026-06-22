//
//  CronBuilderView.swift
//  LaunchCraft
//
//  cron 式を、各フィールドのプルダウン＋プリセットで組み立てる。
//  生の TextField ではなく「見やすく書きやすい」入力を目指す。
//

import SwiftUI

struct CronBuilderView: View {
    @Binding var job: ShellJob

    // よく使う式（5フィールドまとめて設定）。表示ラベルはローカライズされる。
    private let wholePresets: [(LocalizedStringKey, String)] = [
        ("毎分",            "* * * * *"),
        ("5分ごと",         "*/5 * * * *"),
        ("15分ごと",        "*/15 * * * *"),
        ("30分ごと",        "*/30 * * * *"),
        ("毎時0分",         "0 * * * *"),
        ("毎日 9:00",       "0 9 * * *"),
        ("平日 9:00",       "0 9 * * 1-5"),
        ("毎週月曜 9:00",   "0 9 * * 1"),
        ("毎月1日 9:00",    "0 9 1 * *")
    ]

    // 各フィールドのプリセット候補（cron トークンは翻訳しない）
    private let fieldPresets: [[String]] = [
        ["*", "0", "*/5", "*/10", "*/15", "*/30", "0,30"],     // 分
        ["*", "0", "*/2", "*/3", "*/6", "9", "0,12", "9-17"],  // 時
        ["*", "1", "15", "1,15", "L=末日は非対応"],            // 日
        ["*", "1", "6", "12"],                                 // 月
        ["*", "0", "1", "5", "6", "1-5", "0,6"]                // 曜日
    ]

    // フィールド名は語が衝突する（月=Month/Monday など）ため独立キーで翻訳する。
    private var fieldLabels: [String] {
        [
            String(localized: "cron.field.minute",  defaultValue: "分"),
            String(localized: "cron.field.hour",    defaultValue: "時"),
            String(localized: "cron.field.day",     defaultValue: "日"),
            String(localized: "cron.field.month",   defaultValue: "月"),
            String(localized: "cron.field.weekday", defaultValue: "曜日")
        ]
    }
    private var fieldHints: [String] {
        ["0-59", "0-23", "1-31", "1-12",
         String(localized: "cron.hint.weekday", defaultValue: "0-7 (0,7=日)")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // まとめプリセット
            VStack(alignment: .leading, spacing: 5) {
                Text("よく使う設定")
                    .font(.caption).foregroundStyle(.secondary)
                FlowPresets(presets: wholePresets) { expr in
                    job.cronExpression = expr
                }
            }

            // フィールドごとの入力
            HStack(alignment: .top, spacing: 8) {
                ForEach(0..<5, id: \.self) { idx in
                    cronField(idx)
                }
            }

            // 結果プレビュー
            previewBox
        }
    }

    private func cronField(_ idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fieldLabels[idx])
                .font(.caption).bold()
            HStack(spacing: 2) {
                TextField("", text: fieldBinding(idx), prompt: Text(verbatim: fieldHints[idx]))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    .font(.system(.body, design: .monospaced))
                Menu {
                    ForEach(fieldPresets[idx], id: \.self) { preset in
                        if preset.contains("非対応") {
                            Text(LocalizedStringKey(preset)).foregroundStyle(.secondary)
                        } else {
                            Button(preset) { setComponent(idx, preset) }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
            }
            Text(verbatim: fieldHints[idx])
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var previewBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("cron 式:")
                    .font(.caption).foregroundStyle(.secondary)
                Text(verbatim: components.joined(separator: " "))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            switch translation {
            case .success(let desc):
                Label(desc, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failure(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("「日」と「曜日」を同時に指定すると launchd では両方一致が条件になります（cron の OR とは異なります）。片方は * を推奨。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: ロジック

    /// cron 式を5要素に正規化
    private var components: [String] {
        var parts = job.cronExpression
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        while parts.count < 5 { parts.append("*") }
        return Array(parts.prefix(5))
    }

    private func component(_ idx: Int) -> String { components[idx] }

    private func setComponent(_ idx: Int, _ value: String) {
        var parts = components
        parts[idx] = value.isEmpty ? "*" : value
        job.cronExpression = parts.joined(separator: " ")
    }

    private func fieldBinding(_ idx: Int) -> Binding<String> {
        Binding(
            get: { component(idx) },
            set: { setComponent(idx, $0) }
        )
    }

    private enum Translation {
        case success(String)
        case failure(String)
    }

    private var translation: Translation {
        do {
            let schedule = try CronTranslator.toLaunchd(job.cronExpression)
            switch schedule {
            case .interval(let secs):
                return .success(String(localized: "cron.preview.interval", defaultValue: "→ \(secs) 秒ごと (StartInterval) に変換"))
            case .calendar(let entries):
                return .success(String(localized: "cron.preview.calendar", defaultValue: "→ \(entries.count) 個の実行時刻 (StartCalendarInterval) に変換"))
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

/// プリセットボタンを折り返して並べる
struct FlowPresets: View {
    let presets: [(LocalizedStringKey, String)]
    let action: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(presets, id: \.1) { item in
                Button(item.0) { action(item.1) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}
