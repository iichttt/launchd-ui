import LaunchdCore
import SwiftUI

/// Lists the options this job's program accepts, and remembers which of them the run
/// dialog should offer.
struct FlagsTab: View {
    var job: LaunchdJob

    @State private var flags: [ProgramFlag] = []
    @State private var offered: Set<String> = []
    @State private var detectError: String?
    @State private var saveError: String?
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView("Asking the program for its options…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detectError {
                ContentUnavailableView {
                    Label("No options found", systemImage: "questionmark.square.dashed")
                } description: {
                    Text(detectError)
                } actions: {
                    Button("Try Again") { Task { await detect() } }
                }
            } else {
                list
            }
        }
        .task { await detect() }
    }

    private var list: some View {
        Form {
            Section {
                ForEach(flags) { flag in
                    Toggle(isOn: binding(for: flag)) {
                        Text(flag.name)
                            .font(.system(.body, design: .monospaced))
                        if !flag.summary.isEmpty { Text(flag.summary) }
                    }
                }
            } header: {
                Text("Offer when running")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ticked options become choices in the dialog that appears when "
                        + "you run this agent. Running with options starts the program "
                        + "directly, so launchd is not involved.")
                    if let saveError {
                        Text(saveError).foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for flag: ProgramFlag) -> Binding<Bool> {
        Binding(
            get: { offered.contains(flag.name) },
            set: { isOn in
                if isOn { offered.insert(flag.name) } else { offered.remove(flag.name) }
                save()
            })
    }

    private func save() {
        // The full records are stored, not just the names, so the run dialog knows each
        // option's placeholder and description without asking the program again.
        saveError = nil
        do { try FlagStore.setOfferedFlags(flags.filter { offered.contains($0.name) }, for: job.label) }
        catch { saveError = error.localizedDescription }
    }

    private func detect() async {
        loading = true
        detectError = nil
        let config = job.plist
        do {
            // Spawns the program, so it must not run on the main actor.
            let found = try await Task.detached { try FlagDiscovery.discover(config: config) }.value
            flags = found
            // Ticks survive a re-detect, but an option the program has since dropped
            // does not come back with them.
            let names = Set(found.map(\.name))
            offered = Set(FlagStore.offeredFlags(for: job.label).map(\.name)).intersection(names)
        } catch {
            detectError = error.localizedDescription
        }
        loading = false
    }
}
