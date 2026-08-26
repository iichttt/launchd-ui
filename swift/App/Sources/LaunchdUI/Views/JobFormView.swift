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
            Form {
                Section {
                    LabeledContent("Label") {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("com.example.my-agent", text: Binding(
                                get: { config.label },
                                set: { newValue in
                                    // launchd labels cannot contain whitespace.
                                    let label = newValue.filter { !$0.isWhitespace }
                                    config.label = label
                                    // Creating a new agent pre-fills log paths from the
                                    // label, matching the upstream form's convenience.
                                    if !isEditing, !label.isEmpty {
                                        let logDir = PlistStore.homeDirectory
                                            .appending(path: "Library/Logs/launchd-ui").path
                                        config.standardOutPath = "\(logDir)/\(label).stdout.log"
                                        config.standardErrorPath = "\(logDir)/\(label).stderr.log"
                                    }
                                }
                            ))
                            .disabled(isEditing)
                            caption("Unique identifier. Use reverse domain notation (e.g. com.yourname.task).")
                        }
                    }

                    LabeledContent("Program Arguments") {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("/usr/bin/my-program --flag value", text: $argumentsText)
                            caption("The command to execute, then its arguments. Quote arguments containing spaces.")
                        }
                    }
                }

                Section("Startup") {
                    Toggle(isOn: Binding(
                        get: { config.runAtLoad ?? false },
                        set: { config.runAtLoad = $0 })
                    ) {
                        Text("Run at Load")
                        Text("Start automatically when loaded by launchd.")
                    }

                    Toggle(isOn: Binding(
                        get: { config.keepAlive ?? false },
                        set: { config.keepAlive = $0 })
                    ) {
                        Text("Keep Alive")
                        Text("Restart automatically if the process exits.")
                    }
                }

                Section("Schedule") {
                    Picker("Trigger", selection: $scheduleType) {
                        ForEach(ScheduleType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }

                    switch scheduleType {
                    case .none:
                        EmptyView()

                    case .interval:
                        LabeledContent("Every") {
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("300", text: $intervalSeconds)
                                    .frame(width: 100)
                                caption("Seconds. 300 = every 5 minutes, 3600 = every hour.")
                            }
                        }

                    case .calendar:
                        calendarRows
                    }
                }

                if scheduleType == .calendar {
                    nextRunsSection
                }

                Section("Paths") {
                    TextField("Standard Out", text: Binding(
                        get: { config.standardOutPath ?? "" },
                        set: { config.standardOutPath = $0 }))
                    TextField("Standard Error", text: Binding(
                        get: { config.standardErrorPath ?? "" },
                        set: { config.standardErrorPath = $0 }))
                    TextField("Working Directory", text: Binding(
                        get: { config.workingDirectory ?? "" },
                        set: { config.workingDirectory = $0 }))
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        // Sized rather than pinned, so a long argument list or a small display both work.
        .frame(minWidth: 520, idealWidth: 580, minHeight: 520, idealHeight: 680)
    }

    // MARK: - Fields

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var calendarRows: some View {
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
            numberField("At hour", value: Binding(
                get: { calendarInterval.hour },
                set: { calendarInterval.hour = $0 }), placeholder: "9")
        case .range:
            numberField("From hour", value: Binding(
                get: { hourFrom }, set: { hourFrom = $0 ?? 0 }), placeholder: "7")
            numberField("To hour", value: Binding(
                get: { hourTo }, set: { hourTo = $0 ?? 0 }), placeholder: "23")
            LabeledContent("") {
                caption("Runs every hour in this range (7 to 23 = 7:00, 8:00, … 23:00).")
            }
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
    }

    /// Live preview of the next few firings, so a schedule can be sanity-checked before saving.
    @ViewBuilder
    private var nextRunsSection: some View {
        let intervals = hourMode == .range
            ? CalendarUtils.expandHourRange(base: calendarInterval, from: hourFrom, to: hourTo)
            : [calendarInterval]
        let upcoming = CalendarUtils.nextOccurrences(multi: intervals, count: 5)
        if !upcoming.isEmpty {
            Section("Next runs") {
                ForEach(upcoming, id: \.self) { date in
                    Text(CalendarUtils.formatDateTime(date))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func numberField(
        _ title: String, value: Binding<Int?>, placeholder: String
    ) -> some View {
        LabeledContent(title) {
            TextField(placeholder, text: Binding(
                get: { value.wrappedValue.map(String.init) ?? "" },
                set: { value.wrappedValue = Int($0) }
            ))
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
