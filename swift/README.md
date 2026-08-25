# launchd-ui — Swift port

A native SwiftUI port of the Tauri app, replacing the Rust backend and React frontend.

## Layout

```
Core/            LaunchdCore — models plus launchd/plist logic. No SwiftUI.
                 Builds and verifies with plain Command Line Tools.
App/             LaunchdUI — the SwiftUI app. Depends on Core. Requires Xcode.
Resources/       Info.plist and entitlements used to assemble the bundle.
scripts/         build-app.sh — build, bundle, sign, optionally notarize.
```

The split is deliberate: it keeps every piece of portable logic testable without a
15GB Xcode install, and confines the Xcode dependency to the view layer.

## What maps to what

| Tauri original | Swift |
|---|---|
| `src-tauri/src/types.rs` | `Core/…/Models/Models.swift` |
| `src-tauri/src/launchctl.rs` | `Core/…/Services/Launchctl.swift` |
| `src-tauri/src/plist_util.rs` | `Core/…/Services/PlistStore.swift` (`PropertyListSerialization`) |
| `src-tauri/src/commands.rs` | `Core/…/Services/JobService.swift` |
| `src/lib/calendar-utils.ts` | `Core/…/Services/CalendarUtils.swift` |
| `src/components/CommandPanel.tsx` | `Core/…/Services/CommandBuilder.swift` |
| `src/hooks/useJobs.ts` + `App.tsx` state | `App/…/ViewModels/JobsModel.swift` |
| `src/components/*.tsx` | `App/…/Views/*.swift` |
| 13 shadcn/ui components | dropped — native SwiftUI controls |

## Verifying the core

Command Line Tools ships neither XCTest nor Swift Testing (both live inside Xcode), so
the checks are a plain executable that exits non-zero on failure:

```sh
cd Core && swift run CoreChecks
```

It ports the assertions from the Rust `launchctl`/`commands` test modules and the
`calendar-utils` vitest suite, and adds coverage for argument parsing, the command
builder, and a plist write/read round trip.

## Building the app

```sh
./scripts/build-app.sh
```

**Requires Xcode**, not just Command Line Tools: SwiftUI's `@State` is a macro whose
plugin (`libSwiftUIMacros.dylib`) ships only with Xcode. The script fails early with
that explanation if the active toolchain is CLT.

## Signing

The identity is a single variable, so moving from a local build to a distributable one
changes nothing else:

```sh
# Ad-hoc — no certificate, runs on this Mac, Gatekeeper warns elsewhere
./scripts/build-app.sh

# Apple Development certificate — runs on your own machines
SIGN_IDENTITY="Apple Development: You (TEAMID)" ./scripts/build-app.sh

# Developer ID + notarization — distributable to anyone
SIGN_IDENTITY="Developer ID Application: You (TEAMID)" \
  NOTARIZE=1 NOTARY_PROFILE=my-profile ./scripts/build-app.sh
```

List available identities with `security find-identity -v -p codesigning`.

A free Apple Development certificate is issued through Xcode's automatic signing for
Personal Team Apple IDs; the developer portal's manual certificate flow requires paid
Apple Developer Program membership.

The app is signed with the hardened runtime and is **not** sandboxed — it shells out to
`/bin/launchctl` and reads plists across `LaunchAgents` and `LaunchDaemons`, which the
App Sandbox forbids.
