import LaunchdCore
import SwiftUI

/// Asks which of the job's chosen options to apply, then runs the program with them.
struct RunOptionsSheet: View {
    var entry: JobListEntry

    @Environment(\.dismiss) private var dismiss

    @State private var config: PlistConfig?
    @State private var flags: [ProgramFlag] = []
    @State private var selected: Set<String> = []
    @State private var values: [String: String] = [:]
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Options") {
                    ForEach(flags) { flag in
                        Toggle(isOn: selection(for: flag)) {
                            Text(flag.name)
                                .font(.system(.body, design: .monospaced))
                            if !flag.summary.isEmpty { Text(flag.summary) }
                        }
                        // The value field only matters once its option is on, so it
                        // appears with it rather than sitting there empty.
                        if flag.takesValue, selected.contains(flag.name) {
                            LabeledContent(flag.valuePlaceholder ?? "Value") {
                                TextField(
                                    text: value(for: flag),
                                    prompt: Text(flag.valuePlaceholder ?? "value")
                                ) {
                                    Text("\(flag.name) value")
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }

                // Exactly what will be run, so there is no guessing about quoting or
                // which options made it in.
                Section("Command") {
                    Text(preview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Group {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("Starts the program directly, so launchd is not involved and "
                            + "the list's PID and Last Run will not change.")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Run") { run() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(config == nil)
            }
            .padding(12)
        }
        .frame(minWidth: 540, idealWidth: 600, minHeight: 400)
        .task { await load() }
    }

    /// The options actually applied. An option that needs a value is left out until it
    /// has one, since passing it bare would only make the program complain.
    private var extraArguments: [String] {
        flags.flatMap { flag -> [String] in
            guard selected.contains(flag.name) else { return [] }
            guard flag.takesValue else { return [flag.name] }
            let value = (values[flag.name] ?? "").trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? [] : [flag.name, value]
        }
    }

    private var preview: String {
        guard let arguments = config?.programArguments, !arguments.isEmpty else { return "…" }
        return (arguments + extraArguments)
            .map(CommandBuilder.shellQuote)
            .joined(separator: " ")
    }

    private func selection(for flag: ProgramFlag) -> Binding<Bool> {
        Binding(
            get: { selected.contains(flag.name) },
            set: { isOn in
                if isOn { selected.insert(flag.name) } else { selected.remove(flag.name) }
            })
    }

    private func value(for flag: ProgramFlag) -> Binding<String> {
        Binding(
            get: { values[flag.name] ?? "" },
            set: { values[flag.name] = $0 })
    }

    private func load() async {
        flags = FlagStore.offeredFlags(for: entry.label)
        let path = entry.plistPath
        do {
            // jobDetail spawns launchctl, so it stays off the main actor.
            let job = try await Task.detached { try JobService.jobDetail(plistPath: path) }.value
            config = job.plist
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func run() {
        guard let config else { return }
        do {
            try JobService.runProgram(config: config, extraArguments: extraArguments)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
