//
//  ScheduleEditorView.swift
//  AutoShell-execer
//
//  スケジュール設定 UI。launchd「かんたん」モードと cron モードを切り替える。
//

import SwiftUI

struct ScheduleEditorView: View {
    @Binding var job: ShellJob

    private var weekdayNames: [String] { WeekdaySymbols.all }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("入力モード", selection: $job.scheduleMode) {
                ForEach(ScheduleMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if job.scheduleMode == .launchd {
                launchdEditor
            } else {
                CronBuilderView(job: $job)
            }

            schedulePreview
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: launchd かんたんモード

    @ViewBuilder
    private var launchdEditor: some View {
        Picker("種類", selection: $job.launchdKind) {
            ForEach(LaunchdKind.allCases) { kind in
                Text(kind.label).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        if job.launchdKind == .interval {
            HStack {
                Text("実行間隔")
                TextField("値", value: $job.intervalValue, format: .number)
                    .labelsHidden()
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $job.intervalUnit) {
                    ForEach(IntervalUnit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
                Text("ごとに実行")
                    .foregroundStyle(.secondary)
            }
            Text("間隔モードはアプリ読み込み時点からの相対時間で動きます（壁時計の :00 等には揃いません）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            calendarEditor
        }
    }

    @ViewBuilder
    private var calendarEditor: some View {
        Picker("頻度", selection: $job.calendar.frequency) {
            ForEach(CalendarFrequency.allCases) { f in
                Text(f.label).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        switch job.calendar.frequency {
        case .hourly:
            HStack {
                Text("毎時")
                minutePicker
                Text("分に実行")
            }
        case .daily:
            HStack {
                Text("毎日")
                timePickers
            }
        case .weekly:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { day in
                        weekdayToggle(day)
                    }
                }
                HStack {
                    Text("時刻")
                    timePickers
                }
            }
        case .monthly:
            HStack {
                Text("毎月")
                Picker("", selection: $job.calendar.day) {
                    ForEach(1...31, id: \.self) { d in
                        Text(verbatim: "\(d)").tag(d)
                    }
                }
                .labelsHidden()
                .frame(width: 70)
                Text(String(localized: "schedule.monthly.daySuffix", defaultValue: "日"))
                timePickers
            }
        }
    }

    private var timePickers: some View {
        HStack(spacing: 4) {
            hourPicker
            Text(verbatim: ":")
            minutePicker
        }
    }

    private var hourPicker: some View {
        Picker("", selection: $job.calendar.hour) {
            ForEach(0..<24, id: \.self) { h in
                Text(verbatim: String(format: "%02d", h)).tag(h)
            }
        }
        .labelsHidden()
        .frame(width: 70)
    }

    private var minutePicker: some View {
        Picker("", selection: $job.calendar.minute) {
            ForEach(0..<60, id: \.self) { m in
                Text(verbatim: String(format: "%02d", m)).tag(m)
            }
        }
        .labelsHidden()
        .frame(width: 70)
    }

    private func weekdayToggle(_ day: Int) -> some View {
        let isOn = job.calendar.weekdays.contains(day)
        return Button {
            if isOn { job.calendar.weekdays.remove(day) }
            else { job.calendar.weekdays.insert(day) }
        } label: {
            Text(weekdayNames[day])
                .frame(width: 32, height: 28)
                .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    // MARK: プレビュー

    private var schedulePreview: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: "clock.fill")
                .foregroundStyle(.tint)
            Text(job.scheduleSummary)
                .font(.callout.weight(.medium))
            Spacer()
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}
