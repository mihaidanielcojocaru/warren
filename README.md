# Warren

A macOS menu bar app that lists your Tailscale devices and connects to them in one
click: SSH into a machine, or open a file transfer session.

No Dock icon, no main window, no third-party dependencies — Foundation, SwiftUI and
AppKit only. Warren never handles credentials; authentication is delegated to `ssh`
and the keys you already have.

## Requirements

- macOS 14.0 or later
- Xcode 16 or later (developed against Xcode 26.6 / Swift 6.3, language mode 5)
- The Tailscale CLI, found automatically at one of:
  `/Applications/Tailscale.app/Contents/MacOS/tailscale`, `/usr/local/bin/tailscale`,
  `/opt/homebrew/bin/tailscale`, `/usr/bin/tailscale` — or set explicitly in Settings.

## Build and run

```sh
xcodebuild build -scheme Warren -destination 'platform=macOS'
xcodebuild test  -scheme Warren -destination 'platform=macOS'
```

Or open `Warren.xcodeproj` and press ⌘R. The status item appears at the right of
the menu bar; there is deliberately no Dock icon (`LSUIElement`).

The test target has no network and no subprocesses: `TailscaleClienting` and
`ProcessRunning` are faked, and the tailnet comes from
`WarrenTests/Fixtures/status-sample.json`.

## Architecture

| Layer | Files | Responsibility |
| --- | --- | --- |
| Models | `Models/TailscaleStatus.swift`, `LossyDecoding.swift` | Wire format. Every field optional or defaulted; decoding degrades, never throws. |
| | `Models/Device.swift`, `TailnetSnapshot.swift` | Domain model the UI is written against, plus `TailnetState`. |
| Services | `Services/ProcessRunner.swift` | `Process` with a timeout, behind `ProcessRunning`. |
| | `Services/TailscaleClient.swift` | `status --json`, `ping`, `set --exit-node`, behind `TailscaleClienting`. |
| | `Services/TerminalLauncher.swift`, `MountManager.swift` | Side effects, protocol-backed. |
| State | `State/DeviceStore.swift`, `Preferences.swift` | Polling loop and settings. |
| UI | `UI/*`, `Actions/DeviceActions.swift` | Presentation only; all side effects go through `DeviceActions`. |
| Root | `App/AppEnvironment.swift` | The one place concrete implementations are chosen. |

### Untrusted input

Device names come from the network. Nothing in the app builds a shell command by
interpolation: `ProcessRunning` takes an argument vector and there is no `sh -c`
variant. The single exception is Terminal.app and iTerm2, which accept a *shell
command line* over AppleScript — those go through `Shell.commandLine`, which
single-quotes every element, and hosts and user names are validated against
`ConnectionTarget` first. `ShellTests` pins this down.

## Distribution

Developer ID + notarization, not the App Store. The App Sandbox is deliberately
**off**: the app spawns the Tailscale CLI and reads `/Library/Tailscale`, neither of
which survives sandboxing.

```sh
# 1. Archive
xcodebuild archive \
  -scheme Warren \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath build/Warren.xcarchive

# 2. Sign with Developer ID (hardened runtime is already on in the project)
codesign --force --options runtime --timestamp \
  --entitlements Warren/Warren.entitlements \
  --sign "Developer ID Application: YOUR NAME (8VBMHL3Y6P)" \
  build/Warren.xcarchive/Products/Applications/Warren.app

codesign --verify --deep --strict --verbose=2 \
  build/Warren.xcarchive/Products/Applications/Warren.app

# 3. Notarize (store credentials once)
xcrun notarytool store-credentials "warren-notary" \
  --apple-id "you@example.com" --team-id 8VBMHL3Y6P --password "app-specific-password"

ditto -c -k --keepParent \
  build/Warren.xcarchive/Products/Applications/Warren.app build/Warren.zip

xcrun notarytool submit build/Warren.zip --keychain-profile "warren-notary" --wait

# 4. Staple and verify
xcrun stapler staple build/Warren.xcarchive/Products/Applications/Warren.app
spctl -a -vvv -t exec build/Warren.xcarchive/Products/Applications/Warren.app
```

Re-zip **after** stapling for distribution — the ticket is stapled to the `.app`,
not to the archive you submitted.

The Release build is a universal binary; confirm with
`lipo -info Warren.app/Contents/MacOS/Warren` (expect `x86_64 arm64`).

## Permissions

Warren asks for as little as it can, and only when you use the feature that needs it.

| Prompt | When | Why | If you decline |
| --- | --- | --- | --- |
| **Automation** — "Warren wants access to control Terminal" | First SSH using Terminal.app or iTerm2 | Those two are driven by AppleScript (`do script`), the only supported way to open a command in a new window. Declared as `NSAppleEventsUsageDescription`, and entitled with `com.apple.security.automation.apple-events` because the hardened runtime blocks Apple events otherwise. | Warren shows an alert naming System Settings › Privacy & Security › Automation. Ghostty, WezTerm, Kitty and Alacritty take an argument vector and need no permission at all. |
| **Login item** | Turning on "Launch at login" | `SMAppService.mainApp` registration. macOS may show its own "Warren added a login item" notification. | Nothing else is affected. |
| **File access** | Mounting with sshfs | Creates `~/Warren Mounts/<device>`. This is `sshfs`'s own access, not Warren's. | Warren falls back to an `sftp://` handler, then to offering the command on the clipboard. |

Warren does **not** request Screen Recording, Accessibility, Full Disk Access, camera,
microphone, or contacts, and it opens no listening sockets. It has no Keychain
entitlement and stores no secrets: every setting lives in `UserDefaults`.

## Settings

Default SSH user name · per-device user name overrides (keyed by DNS name) ·
terminal app · what a left-click does · poll interval (5–60s) · path to the
`tailscale` binary, with a validity check · launch at login.

Polling runs at your chosen interval while the menu is open and drops to once a
minute while it is closed, which keeps the status icon honest without spawning a
process every ten seconds in the background.
