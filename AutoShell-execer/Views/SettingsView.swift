//
//  SettingsView.swift
//  LaunchCraft
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: 0) {
            // ヘッダー
            HStack {
                Text("設定")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            // コンテンツ
            Form {
                Section {
                    LabeledContent("表示件数") {
                        Stepper(
                            value: $settings.menuBarJobCount,
                            in: 3...20,
                            step: 1
                        ) {
                            Text("\(settings.menuBarJobCount) 件")
                                .monospacedDigit()
                                .frame(minWidth: 36, alignment: .trailing)
                        }
                    }
                } header: {
                    Text("メニューバー")
                } footer: {
                    Text("メニューバーのパネルに表示するジョブの最大件数（3〜20 件）")
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 380, height: 230)
    }
}
