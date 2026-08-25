import Foundation
import LaunchdCore

// Ports the assertions from src-tauri/src/{launchctl,commands}.rs and
// src/__tests__/calendar-utils.test.ts, plus coverage for the argument parser and
// command builder that the TypeScript app tested indirectly.

// MARK: - launchctl list parsing

Check.suite("launchctl list parsing") {
    let output = "PID\tStatus\tLabel\n1234\t0\tcom.example.running\n-\t78\tcom.example.stopped\n"
    let result = Launchctl.parseListOutput(output)
    Check.equal(result.count, 2, "parses two services")
    Check.equal(result[0].label, "com.example.running", "first label")
    Check.equal(result[0].pid, 1234, "first pid")
    Check.equal(result[0].lastExitCode, 0, "first exit code")
    Check.equal(result[1].label, "com.example.stopped", "second label")
    Check.equal(result[1].pid, nil, "a '-' pid parses as nil")
    Check.equal(result[1].lastExitCode, 78, "second exit code")

    Check.expect(Launchctl.parseListOutput("PID\tStatus\tLabel\n").isEmpty,
                 "header-only output yields nothing")

    let malformed = Launchctl.parseListOutput("PID\tStatus\tLabel\nbad line\n1234\t0\tcom.example.test\n")
    Check.equal(malformed.count, 1, "malformed lines are skipped")
    Check.equal(malformed.first?.label, "com.example.test", "valid line still parsed")
}

// MARK: - Home-agent classification

Check.suite("home agent classification") {
    func cfg(program: String? = nil, args: [String]? = nil) -> PlistConfig {
        PlistConfig(label: "test", program: program, programArguments: args)
    }
    let home = "/Users/x"

    Check.expect(JobService.isAppPath("/Applications/Mailspring.app/Contents/MacOS/Mailspring"),
                 "/Applications binary is an app path")
    Check.expect(JobService.isAppPath(
        "/Users/x/Library/Application Support/Google/GoogleUpdater/Current/GoogleUpdater.app/Contents/MacOS/GoogleUpdater"),
                 "updater under Application Support is an app path")
    Check.expect(!JobService.isAppPath("/bin/bash"), "/bin/bash is not an app path")
    Check.expect(!JobService.isAppPath("/Users/x/instagent-launcher.sh"),
                 "a home script is not an app path")

    Check.expect(JobService.referencesHomePath("/Users/x/instagent-launcher.sh", home: home),
                 "bare home path is referenced")
    Check.expect(JobService.referencesHomePath(
        "cd \"/Users/x/ClaudeCoding/vimeo\" && python3 refresh.py", home: home),
                 "home path inside a zsh -c string is referenced")
    Check.expect(!JobService.referencesHomePath(
        "/Users/x/Library/Application Support/Google/GoogleUpdater.app/foo", home: home),
                 "vendor app under home is not a user script")
    Check.expect(!JobService.referencesHomePath("/bin/bash", home: home),
                 "a non-home path is not referenced")

    let instagent = cfg(args: ["/bin/bash", "\(home)/instagent-launcher.sh"])
    Check.expect(JobService.isHomeAgent(source: .userAgent, config: instagent, home: home),
                 "interpreter running a home script is a home agent")

    let vimeo = cfg(args: ["/bin/zsh", "-l", "-c",
                           "cd \"\(home)/ClaudeCoding/vimeo\" && python3 refresh.py"])
    Check.expect(JobService.isHomeAgent(source: .userAgent, config: vimeo, home: home),
                 "zsh -c with a home path is a home agent")

    let mailspring = cfg(args: ["/Applications/Mailspring.app/Contents/MacOS/Mailspring"])
    Check.expect(!JobService.isHomeAgent(source: .userAgent, config: mailspring, home: home),
                 "vendor app in /Applications is not a home agent")

    let google = cfg(program:
        "\(home)/Library/Application Support/Google/GoogleUpdater.app/Contents/MacOS/GoogleUpdater")
    Check.expect(!JobService.isHomeAgent(source: .userAgent, config: google, home: home),
                 "vendor auto-updater is not a home agent")

    Check.expect(!JobService.isHomeAgent(source: .systemAgent, config: instagent, home: home),
                 "Home is a strict subset of UserAgent")
}

// MARK: - Calendar intervals

Check.suite("calendar intervals") {
    Check.expect(CalendarUtils.detectHourRange([CalendarInterval(minute: 0, hour: 9)]) == nil,
                 "a single interval is never a range")

    let contiguous = (9...11).map { CalendarInterval(minute: 30, hour: $0) }
    let range = CalendarUtils.detectHourRange(contiguous)
    Check.equal(range?.from, 9, "range starts at 9")
    Check.equal(range?.to, 11, "range ends at 11")
    Check.equal(range?.base.minute, 30, "range keeps the shared minute")
    Check.expect(range?.base.hour == nil, "range clears the hour on the base")

    let unordered = [11, 9, 10].map { CalendarInterval(minute: 0, hour: $0) }
    Check.equal(CalendarUtils.detectHourRange(unordered)?.from, 9,
                "unordered intervals still detect a range")

    Check.expect(CalendarUtils.detectHourRange(
        [9, 11].map { CalendarInterval(minute: 0, hour: $0) }) == nil,
                 "non-contiguous hours are not a range")
    Check.expect(CalendarUtils.detectHourRange([
        CalendarInterval(minute: 0, hour: 9), CalendarInterval(minute: 30, hour: 10),
    ]) == nil, "differing minutes are not a range")
    Check.expect(CalendarUtils.detectHourRange([
        CalendarInterval(minute: 0), CalendarInterval(minute: 0),
    ]) == nil, "nil hours are not a range")

    let expanded = CalendarUtils.expandHourRange(
        base: CalendarInterval(minute: 30, weekday: 1), from: 9, to: 10)
    Check.equal(expanded.count, 2, "expands to two intervals")
    Check.equal(expanded.first, CalendarInterval(minute: 30, hour: 9, weekday: 1),
                "expansion preserves weekday and minute")
    Check.equal(expanded.last?.hour, 10, "expansion covers the end hour")

    Check.equal(CalendarUtils.expandHourRange(
        base: CalendarInterval(minute: 0), from: 9, to: 9).count, 1,
                "from == to expands to one interval")
    Check.expect(CalendarUtils.expandHourRange(
        base: CalendarInterval(minute: 0), from: 10, to: 9).isEmpty,
                 "from > to expands to nothing")

    let specific = CalendarUtils.nextOccurrences(CalendarInterval(minute: 30, hour: 14), count: 3)
    Check.equal(specific.count, 3, "returns the requested number of occurrences")
    Check.expect(specific.allSatisfy {
        let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
        return c.hour == 14 && c.minute == 30
    }, "occurrences honour hour and minute")
    Check.expect(specific.allSatisfy { $0 > Date() }, "occurrences are in the future")

    let hourly = CalendarUtils.nextOccurrences(CalendarInterval(minute: 0), count: 3)
    Check.equal(hourly.count, 3, "a nil hour still yields occurrences")
    Check.expect(hourly.allSatisfy { Calendar.current.component(.minute, from: $0) == 0 },
                 "a nil hour fires on the minute every hour")

    // launchd Weekday is 0-based with Sunday == 0; Foundation's Calendar is 1-based.
    let mondays = CalendarUtils.nextOccurrences(
        CalendarInterval(minute: 0, hour: 9, weekday: 1), count: 3)
    Check.equal(mondays.count, 3, "weekday schedule yields occurrences")
    Check.expect(mondays.allSatisfy { Calendar.current.component(.weekday, from: $0) == 2 },
                 "launchd weekday 1 maps to Foundation Monday (2)")

    let merged = CalendarUtils.nextOccurrences(
        multi: [CalendarInterval(minute: 0, hour: 9), CalendarInterval(minute: 0, hour: 17)],
        count: 3)
    Check.equal(merged.count, 3, "multi merges to the requested count")
    Check.expect(zip(merged, merged.dropFirst()).allSatisfy { $0 < $1 }, "multi results are sorted")
    Check.equal(Set(merged).count, merged.count, "multi results are deduplicated")

    // The occurrence search skips runs of candidates that cannot match rather than
    // testing every minute in a 400-day window; these pin the skipped paths down.
    let impossible = CalendarUtils.nextOccurrences(
        CalendarInterval(minute: 0, hour: 0, day: 30, month: 2), count: 5)
    Check.expect(impossible.isEmpty, "an impossible date (Feb 30) terminates with no occurrences")

    let yearly = CalendarUtils.nextOccurrences(
        CalendarInterval(minute: 0, hour: 0, day: 1, month: 1), count: 5)
    Check.expect(yearly.count == 1, "a yearly schedule finds its one firing inside 400 days")
    Check.expect(yearly.allSatisfy {
        let c = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: $0)
        return c.month == 1 && c.day == 1 && c.hour == 0 && c.minute == 0
    }, "the yearly firing lands on Jan 1 00:00")

    let dayOfMonth = CalendarUtils.nextOccurrences(
        CalendarInterval(minute: 0, hour: 12, day: 29), count: 3)
    Check.equal(dayOfMonth.count, 3, "a day-of-month schedule yields occurrences")
    Check.expect(dayOfMonth.allSatisfy { Calendar.current.component(.day, from: $0) == 29 },
                 "day-of-month occurrences all land on the 29th")

    // A nil minute is a wildcard, so consecutive minutes of the matching hour fire.
    let wildcardMinute = CalendarUtils.nextOccurrences(CalendarInterval(hour: 23), count: 3)
    Check.equal(wildcardMinute.count, 3, "a nil minute still yields occurrences")
    Check.expect(wildcardMinute.allSatisfy { Calendar.current.component(.hour, from: $0) == 23 },
                 "a nil minute fires every minute of the given hour")

    Check.expect(
        CalendarUtils.nextOccurrences(CalendarInterval(minute: 0), count: 3)
            .allSatisfy { Calendar.current.component(.second, from: $0) == 0 },
        "occurrences land on exact minute boundaries")

    Check.equal(CalendarUtils.format((7...9).map { CalendarInterval(minute: 0, hour: $0) }),
                "Every day at :00 (7:00–9:00)", "formats a detected hour range")
    Check.equal(CalendarUtils.format([CalendarInterval(minute: 5, hour: 9, weekday: 1)]),
                "Every Monday at 09:05", "formats a weekly schedule")
    Check.equal(CalendarUtils.format([CalendarInterval(minute: 15)]),
                "Every day every hour at :15", "formats an every-hour schedule")
}

// MARK: - Argument parsing

Check.suite("argument parsing") {
    Check.equal(ArgumentParser.parse("/usr/bin/cmd --flag value"),
                ["/usr/bin/cmd", "--flag", "value"], "splits on unquoted spaces")
    Check.equal(ArgumentParser.parse("/usr/bin/cmd \"arg with spaces\" tail"),
                ["/usr/bin/cmd", "arg with spaces", "tail"], "keeps double-quoted spans together")
    Check.equal(ArgumentParser.parse("cmd 'a b' c"), ["cmd", "a b", "c"],
                "keeps single-quoted spans together")
    Check.equal(ArgumentParser.parse("cmd   a    b"), ["cmd", "a", "b"], "collapses runs of spaces")
    Check.equal(ArgumentParser.parse(""), [], "empty input yields no arguments")

    let args = ["/bin/zsh", "-c", "cd /tmp && echo hi"]
    Check.equal(ArgumentParser.parse(ArgumentParser.format(args)), args,
                "round-trips through format")
}

// MARK: - Command builder

Check.suite("command builder") {
    Check.equal(CommandBuilder.shellQuote("com.example.agent"), "com.example.agent",
                "safe label is left unquoted")
    Check.equal(CommandBuilder.shellQuote("/Users/x/a-b_c.plist"), "/Users/x/a-b_c.plist",
                "safe path is left unquoted")
    Check.equal(CommandBuilder.shellQuote("a b"), "'a b'", "spaces force quoting")
    Check.equal(CommandBuilder.shellQuote("it's"), #"'it'\''s'"#, "single quotes are escaped")

    func job(_ source: JobSource) -> LaunchdJob {
        LaunchdJob(
            label: "com.example.agent",
            plistPath: "/Users/x/Library/LaunchAgents/com.example.agent.plist",
            source: source, status: .loaded, pid: nil, lastExitCode: nil,
            plist: PlistConfig(label: "com.example.agent"), lastRunAt: nil)
    }

    let userCommands = CommandBuilder.commands(for: job(.userAgent))
    let start = userCommands.first { $0.label == "Start" }
    Check.expect(start?.command.hasPrefix("launchctl bootstrap gui/$(id -u) ") == true,
                 "user agents bootstrap into the gui domain")
    Check.expect(start?.command.contains("sudo") == false, "user agents need no sudo")

    let daemonCommands = CommandBuilder.commands(for: job(.systemDaemon))
    Check.equal(daemonCommands.first { $0.label == "Kickstart" }?.command,
                "sudo launchctl kickstart -k system/com.example.agent",
                "system daemons use the system domain with sudo")

    Check.expect(userCommands.first { $0.label == "Remove" }?.destructive == true,
                 "remove is marked destructive")
}

// MARK: - Plist round trip

Check.suite("plist round trip") {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "launchd-ui-checks-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let path = dir.appending(path: "com.example.roundtrip.plist").path
    let original = PlistConfig(
        label: "com.example.roundtrip",
        program: "/bin/zsh",
        programArguments: ["/bin/zsh", "-c", "echo hi"],
        runAtLoad: true,
        startCalendarInterval: [CalendarInterval(minute: 30, hour: 9, weekday: 1)],
        standardOutPath: "/tmp/out.log",
        environmentVariables: ["FOO": "bar"],
        wakeSystem: true)

    do {
        try PlistStore.writePlist(atPath: path, config: original)
        let reloaded = try PlistStore.parsePlist(atPath: path)
        Check.equal(reloaded.label, original.label, "label survives a round trip")
        Check.equal(reloaded.program, original.program, "program survives a round trip")
        Check.equal(reloaded.programArguments, original.programArguments,
                    "arguments survive a round trip")
        Check.equal(reloaded.runAtLoad, true, "RunAtLoad survives a round trip")
        Check.equal(reloaded.startCalendarInterval?.first,
                    CalendarInterval(minute: 30, hour: 9, weekday: 1),
                    "calendar interval survives a round trip")
        Check.equal(reloaded.environmentVariables?["FOO"], "bar",
                    "environment variables survive a round trip")
        Check.equal(reloaded.wakeSystem, true, "WakeSystem survives a round trip")
        Check.expect(reloaded.keepAlive == nil, "unset keys stay absent")
        Check.expect(reloaded.rawXML.contains("<key>Label</key>"), "raw XML is captured")
    } catch {
        Check.expect(false, "round trip threw: \(error)")
    }

    // Writing raw XML must validate it first.
    do {
        try PlistStore.writeRawPlist(atPath: path, xml: "not a plist")
        Check.expect(false, "invalid raw XML should have thrown")
    } catch {
        Check.expect(true, "invalid raw XML is rejected")
    }
}

Check.report()
