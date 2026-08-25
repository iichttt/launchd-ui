import LaunchdCore
import SwiftUI

struct JobFormView: View {
    var editingJob: LaunchdJob?
    var onSave: (PlistConfig, String?) throws -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var config: PlistConfig
    @State private var argumentsText: String
    @State private var scheduleType: ScheduleType
    @State private var calendarInterval: CalendarInterval
    @State private var hourMode: HourMode
    @State private var hourFrom: Int
    @State private var hourTo: Int
    @State private var intervalSeconds: String
    @State private var error: String?

    enum ScheduleType: String, CaseIterable {
        case none = "No schedule"
        case interval = "Run every N seconds"
        case calendar = "Run at specific time"
    }

    enum HourMode: String, CaseIterable {
        case specific = "Specific hour"
        case every = "Every hour"
        case range = "Hour range"
    }

    private var isEditing: Bool { editingJob != nil }

    init(editingJob: LaunchdJob?, onSave: @escaping (PlistConfig, String?) throws -> Void) {
        self.editingJob = editingJob
        self.onSave = onSave

        let plist = editingJob?.plist ?? PlistConfig(
            label: "", runAtLoad: false, keepAlive: false, disabled: false, wakeSystem: false)
        _config = State(initialValue: plist)
        _argumentsText = State(
            initialValue: plist.programArguments.map(ArgumentParser.format) ?? "")
        _intervalSeconds = State(initialValue: plist.startInterval.map(String.init) ?? "")

        // Reconstruct the editor state the schedule was authored in: an expanded hour
        // range collapses back to from/to, a nil hour means "every hour".
        let intervals = plist.startCalendarInterval ?? []
        let range = CalendarUtils.detectHourRange(intervals)

        if plist.startInterval != nil {
            _scheduleType = State(initialValue: .interval)
        } else if !intervals.isEmpty {
            _scheduleType = State(initialValue: .calendar)
        } else {
            _scheduleType = State(initialValue: .none)
        }

        if let range {
            _hourMode = State(initialValue: .range)
            _calendarInterval = State(initialValue: range.base)
            _hourFrom = State(initialValue: range.from)
            _hourTo = State(initialValue: range.to)
        } else {
            let first = intervals.first
            _hourMode = State(
                initialValue: (first != nil && first?.hour == nil) ? .every : .specific)
            _calendarInterval = State(
                initialValue: first ?? CalendarInterval(minute: 0, hour: 9))
            _hourFrom = State(initialValue: 7)
            _hourTo = State(initialValue: 23)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditing ? "Edit Agent" : "New Agent").font(.headline)
                Spacer()
            }
            .padding(12)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    labelField
                    argumentsField
                    togglesRow
                    scheduleSection
                    pathsSection
                }
                .padding(14)
            }

            Divider()
            HStack {
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 540, height: 640)
    }

    // MARK: - Fields

    private var labelField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Label *").font(.callout.weight(.medium))
            TextField("com.example.my-agent", text: Binding(
                get: { config.label },
                set: { newValue in
                    // launchd labels cannot contain whitespace.
                    let label = newValue.filter { !$0.isWhitespace }
                    config.label = label
                    // Creating a new agent pre-fills log paths from the label, matching
                    // the upstream form's convenience behaviour.
                    if !isEditing, !label.isEmpty {
                        let logDir = PlistStore.homeDirectory
                            .appending(path: "Library/Logs/launchd-ui").path
                        config.standardOutPath = "\(logDir)/\(label).stdout.log"
                        config.standardErrorPath = "\(logDir)/\(label).stderr.log"
                    }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .disabled(isEditing)
            Text("Unique identifier. Use reverse domain notation (e.g. com.yourname.task).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var argumentsField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Program Arguments *").font(.callout.weight(.medium))
            TextField("/usr/bin/my-program --flag value", text: $argumentsText)
                .textFieldStyle(.roundedBorder)
            Text("The command to execute, then its arguments. Quote arguments containing spaces.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var togglesRow: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Run at Load", isOn: Binding(
                    get: { config.runAtLoad ?? false },
                    set: { config.runAtLoad = $0 }))
                Text("Start automatically when loaded by launchd.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Keep Alive", isOn: Binding(
                    get: { config.keepAlive ?? false },
                    set: { config.keepAlive = $0 }))
                Text("Restart automatically if the process exits.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule").font(.callout.weight(.medium))
            Picker("", selection: $scheduleType) {
                ForEach(ScheduleType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()

            switch scheduleType {
            case .none:
                EmptyView()

            case .interval:
                VStack(alignment: .leading, spacing: 4) {
                    TextField("300", text: $intervalSeconds)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Text("e.g. 300 = every 5 minutes, 3600 = every hour.")
                        .font(.caption).foregroundStyle(.secondary)
                }

            case .calendar:
                calendarControls
            }
        }
    }

    @ViewBuilder
    private var calendarControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Hour", selection: Binding(
                get: { hourMode },
                set: { mode in
                    hourMode = mode
                    // Keep the interval consistent with the chosen mode so the preview
                    // and the saved plist agree.
                    if mode == .specific, calendarInterval.hour == nil {
                        calendarInterval.hour = 9
                    } else if mode == .every {
                        calendarInterval.hour = nil
                    }
                }
            )) {
                ForEach(HourMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }

            switch hourMode {
            case .specific:
                numberField("Hour", value: Binding(
                    get: { calendarInterval.hour },
                    set: { calendarInterval.hour = $0 }), placeholder: "9")
            case .range:
                HStack(spacing: 8) {
                    numberField("From", value: Binding(
                        get: { hourFrom }, set: { hourFrom = $0 ?? 0 }), placeholder: "7")
                    numberField("To", value: Binding(
                        get: { hourTo }, set: { hourTo = $0 ?? 0 }), placeholder: "23")
                }
                Text("Runs every hour in this range (7 to 23 = 7:00, 8:00, … 23:00).")
                    .font(.caption).foregroundStyle(.secondary)
            case .every:
                EmptyView()
            }

            numberField("Minute", value: Binding(
                get: { calendarInterval.minute },
                set: { calendarInterval.minute = $0 }), placeholder: "0")

            Picker("Weekday", selection: Binding(
                get: { calendarInterval.weekday ?? -1 },
                set: { calendarInterval.weekday = $0 < 0 ? nil : $0 }
            )) {
                Text("Every day").tag(-1)
                ForEach(0..<7, id: \.self) { i in
                    Text(CalendarUtils.weekdayLabels[i]).tag(i)
                }
            }

            Toggle("Wake system for this schedule", isOn: Binding(
                get: { config.wakeSystem ?? false },
                set: { config.wakeSystem = $0 }))

            nextRunsPreview
        }
    }

    /// Live preview of the next few firings, so a schedule can be sanity-checked before saving.
    @ViewBuilder
    private var nextRunsPreview: some View {
        let intervals = hourMode == .range
            ? CalendarUtils.expandHourRange(base: calendarInterval, from: hourFrom, to: hourTo)
            : [calendarInterval]
        let upcoming = CalendarUtils.nextOccurrences(multi: intervals, count: 5)
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Next runs").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                ForEach(upcoming, id: \.self) { date in
                    Text(CalendarUtils.formatDateTime(date))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var pathsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            textField("Standard Out Path", binding: Binding(
                get: { config.standardOutPath ?? "" },
                set: { config.standardOutPath = $0 }))
            textField("Standard Error Path", binding: Binding(
                get: { config.standardErrorPath ?? "" },
                set: { config.standardErrorPath = $0 }))
            textField("Working Directory", binding: Binding(
                get: { config.workingDirectory ?? "" },
                set: { config.workingDirectory = $0 }))
        }
    }

    private func textField(_ title: String, binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.medium))
            TextField("", text: binding).textFieldStyle(.roundedBorder)
        }
    }

    private func numberField(
        _ title: String, value: Binding<Int?>, placeholder: String
    ) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.callout).frame(width: 60, alignment: .leading)
            TextField(placeholder, text: Binding(
                get: { value.wrappedValue.map(String.init) ?? "" },
                set: { value.wrappedValue = Int($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)
        }
    }

    // MARK: - Save

    private func save() {
        error = nil
        guard !config.label.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Label is required"
            return
        }
        if scheduleType == .calendar, hourMode == .range, hourFrom > hourTo {
            error = "Hour range 'from' must be less than or equal to 'to'"
            return
        }

        var final = config
        let parsed = ArgumentParser.parse(argumentsText.trimmingCharacters(in: .whitespaces))
        final.programArguments = parsed.isEmpty ? nil : parsed
        // launchd needs Program to match argv[0] when ProgramArguments is set.
        final.program = parsed.first ?? config.program

        switch scheduleType {
        case .none:
            final.startInterval = nil
            final.startCalendarInterval = nil
            final.wakeSystem = nil
        case .interval:
            final.startInterval = Int(intervalSeconds)
            final.startCalendarInterval = nil
            final.wakeSystem = nil
        case .calendar:
            final.startInterval = nil
            final.startCalendarInterval = hourMode == .range
                ? CalendarUtils.expandHourRange(
                    base: calendarInterval, from: hourFrom, to: hourTo)
                : [calendarInterval]
            final.wakeSystem = (config.wakeSystem ?? false) ? true : nil
        }

        final.standardOutPath = nonEmpty(final.standardOutPath)
        final.standardErrorPath = nonEmpty(final.standardErrorPath)
        final.workingDirectory = nonEmpty(final.workingDirectory)

        do {
            try onSave(final, editingJob?.plistPath)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespaces)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }
}
