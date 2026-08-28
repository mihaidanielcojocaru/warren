# What I guessed, and what I verified

Verified on this machine (macOS 26.6, Xcode 26.6, Tailscale 1.102.3) unless it says
otherwise. Everything in the first section needs checking on a machine that has the
software installed — none of these five terminals, and neither macFUSE nor sshfs, is
present here.

## 1. Terminal argument syntax — please verify

Only **Terminal.app** exists on this machine. The other five are implemented from
their documented command lines and are unverified end to end.

| App | Arguments Warren passes | Bundle id | In-bundle CLI |
| --- | --- | --- | --- |
| Ghostty | `-e ssh user@host` | `com.mitchellh.ghostty` | `Contents/MacOS/ghostty` |
| iTerm2 | AppleScript: `create window with default profile command "…"` | `com.googlecode.iterm2` | — |
| WezTerm | `start -- ssh user@host` | `com.github.wez.wezterm` | `Contents/MacOS/wezterm-gui`, then `wezterm` |
| Kitty | `ssh user@host` (no `-e`) | `net.kovidgoyal.kitty` | `Contents/MacOS/kitty` |
| Alacritty | `-e ssh user@host` | `org.alacritty` | `Contents/MacOS/alacritty` |
| Terminal.app | AppleScript: `do script "…"` — **verified** | `com.apple.Terminal` | — |

All of it is table-driven in `TerminalApp.arguments(toRun:)`,
`TerminalApp.bundleIdentifier` and `TerminalApp.bundledExecutableNames` at the bottom
of `Services/TerminalLauncher.swift`: one line to correct per app.

**One deliberate deviation from the brief.** You asked for `NSWorkspace.openApplication`
with arguments. Warren tries the CLI inside the app bundle *first* and keeps
`NSWorkspace` as the fallback, because `openApplication` only forwards its `arguments`
when it actually launches the app — if the terminal is already running, which is the
normal case, they are silently dropped and you get an empty window. The bundled CLI
opens a new window either way.

Also unverified, for the same reason: iTerm2's AppleScript command. Both AppleScript
terminals are addressed as `application id "com.…"` rather than by name, which
sidesteps iTerm2 having answered to both "iTerm" and "iTerm2" over the years.

## 2. sshfs and macFUSE — please verify

Neither is installed here, so the mount path has never run.

- macFUSE detection: presence of `/Library/Filesystems/macfuse.fs`.
- Mount options: `-o volname=<device> -o reconnect -o defer_permissions -o noappledouble`.
- Remote path: `user@host:` (the remote home directory).
- Unmount: `/sbin/umount <mountpoint>`.
- Mount point: `~/Warren Mounts/<device>`.

The fallbacks did get exercised in code review but not in anger: with no macFUSE,
Warren tries an `sftp://` handler (Cyberduck, Transmit, Mountain Duck), and if nothing
claims the scheme, offers to copy `sftp user@host` to the clipboard.

## 3. Exit node — untested

Your tailnet currently advertises **no** exit nodes, so "Use as Exit Node" has never
been run for real. The argument vectors are verified against `tailscale set --help`:
`set --exit-node <ip>` and `set --exit-node=` to clear. Failure is surfaced in an
alert that mentions the possible authorization prompt, per the brief.

## 3a. The Tailscale CLI inside Tailscale.app is not self-contained

`/Applications/Tailscale.app/Contents/MacOS/tailscale` is not a standalone CLI on
the standalone (`io.tailscale.ipn.macsys`) build. It brokers through the GUI app,
and when that handshake fails it prints

```
The Tailscale GUI failed to start: The operation couldn't be completed.
(Tailscale.CLIError error 3.)
```

on **stdout** and **exits 0**. So a zero exit code is not evidence of success, and
a client that trusts it reports a confusing "unreadable output" error while a
perfectly good CLI sits at `/usr/local/bin/tailscale`.

`TailscaleClient.fetchStatus` therefore treats a successful *parse* as the only
proof, and walks the candidate list until one answers, promoting whichever did so
the next poll goes straight there. An explicit override in Settings is exempt:
swapping a user-chosen binary for a different one behind their back would be worse
than failing.

This was intermittent — all three binaries answered correctly when probed
directly — so it is a race or a state inside Tailscale rather than a fixed
property of that binary. Warren cannot fix that, only stop being fooled by it.

## 4. Things I checked rather than assumed

- **`tailscale status --json` schema** — read off your live daemon (key names and
  types only, no device data). `Addrs`, `ExtraRecords` and `ClientVersion` all come
  back as `null`, which is why the decoder treats null and missing as the same thing.
- **Timestamps.** `ISO8601DateFormatter` cannot parse Tailscale's output: with
  `.withFractionalSeconds` it rejects `…:00Z`, without it it rejects `…:00.1Z`, and Go's
  `RFC3339Nano` emits both because it trims trailing zeros. Your daemon produced
  `…10:40:00.1Z`. `Date.ISO8601FormatStyle` handles 0–9 fractional digits and both `Z`
  and `+02:00`; that is what `RFC3339` uses. Go's zero time maps to `nil`, not to year 1.
- **`/usr/local/bin/tailscale` is a shell shim** on your machine, exactly as you said,
  so the bundle path is tried first.
- **Ping flags** — `tailscale ping --c 3 <host>`, from `--help`. `--c` really is one
  letter behind two dashes.
- **Exit code when the backend is stopped** — I could not test this without stopping
  your Tailscale, so Warren does not depend on it: it decodes stdout whatever the exit
  code says, and only reports a failure when there is no readable payload.
- **Release build** — universal (`x86_64 arm64`), `LSUIElement`, `LSMinimumSystemVersion
  14.0`, hardened runtime on, `com.apple.security.automation.apple-events` present, no
  sandbox entitlement.
- **It runs.** Launched, polled your real tailnet, and rendered the connected status
  icon — which only appears in the `.ready` state, so the whole path works.

## 5. UI decisions worth a look

The brief allowed either an `NSMenu` or `MenuBarExtra`. Warren uses
`MenuBarExtra(.window)` — a panel — because a real `NSMenu` cannot hold a search field
or distinguish "click the row" from "open the row's submenu" without custom
`NSView`-backed items. Consequences:

- **Hover reveals a ••• button** rather than springing a submenu open. A menu that
  opens itself under a moving cursor is unpleasant in a panel. Right-click gives the
  same actions, as specified.
- **"Offline (N)"** is a collapsed `DisclosureGroup` rather than a submenu.
- **Ping** uses a SwiftUI `.popover` on the row. Popovers inside a `MenuBarExtra`
  window are the one piece of UI still unexercised — worth a look on first run.
- **The device list needs a measured height, not a `maxHeight`.** A `ScrollView`
  inside a `MenuBarExtra` window is proposed no height at all, so `.frame(maxHeight:)`
  alone resolves to zero and the panel renders its header and footer with nothing in
  between. `MenuPanelView.deviceScrollView` measures the content through a
  `PreferenceKey` and pins the frame to it, capped at 420pt. The stack is a plain
  `VStack` rather than a `LazyVStack` for the same reason: a lazy stack in a
  zero-height viewport builds no rows and would measure zero forever.

  Worth knowing that no unit test would have caught this, and one asserting the
  panel's fitting size would have given false confidence: hosting `MenuPanelView` in
  a plain `NSHostingView` lays it out *correctly* even with the bug present. It only
  appears inside a real `MenuBarExtra`. The way to check panel layout is to run it —
  see the harness note below.

## 5a. Checking panel layout

`MenuBarExtra` panels cannot be driven from outside the process (clicking the status
item needs Accessibility, which `osascript` does not have here). To look at the panel
during development, build a throwaway app that hosts `MenuPanelView` in its own
`MenuBarExtra`, and have it click its own status button from inside the process:
walk `NSApp.windows`, find the one whose class name contains `StatusBar`, and send
`performClick(nil)` to the `NSButton` in its content view. That is how the layout bug
above was found and confirmed fixed.
- The panel is not dismissed programmatically after an action. Launching a terminal
  takes focus and closes it anyway, and staying open is useful for the copy actions.
- **"Settings…"** uses `SettingsLink`, so it works without private selectors.

## 5b. Icons

Artwork lives in `icons/` as SVG: `warren-appicon.svg` plus the two menu bar
templates. `icons/make-icons.sh` renders them with `rsvg-convert`, which needs
`brew install librsvg` — not installed here, and there is no Homebrew on this
machine either, so the checked-in PNGs were produced with a small WebKit-based
rasteriser instead (`WKWebView` is the only SVG engine on a stock macOS install).
Either route gives the same result; the script remains the documented one.

What is in the catalog:

- `AppIcon.appiconset` — ten PNGs, each rendered straight from the SVG at its own
  size rather than downscaled from 1024, so the small ones get the vector's own
  hinting. Verified legible at 32px; at 16px it is soft and the drop shadow
  bleeds slightly into the corners, which is normal for macOS at that size.
- `WarrenTemplate.imageset` / `WarrenOfflineTemplate.imageset` — 18pt at @1x and
  @2x (the Mac has no @3x), with `template-rendering-intent: template` so AppKit
  tints them for light, dark and the highlighted state. Confirmed pure black plus
  alpha: filled areas are rgb 0 / alpha 1, everything else alpha 0.

`MenuBarIcon` picks between them: the whole arch only in `.ready`, the struck
arch in every other state including `.loading`. `MenuBarIconTests` pins that down,
since the two assets existing is no guarantee the right one is chosen.

To regenerate after editing the SVGs, either run `icons/make-icons.sh` with
librsvg installed, or re-render at the sizes listed above.

## 6. Naming

Everything user-facing is "Warren": the menu says "Quit Warren", mounts land in
`~/Warren Mounts/`. The brief said "Tailnet", but you asked for the project name back,
and menu text is read from `CFBundleName` (`Support/AppInfo.swift`), so renaming the
product renames the menu with it.

The type names `TailnetSnapshot`, `TailnetState`, `TailnetInfo` and `TailnetFailure`
kept their names on purpose — there "tailnet" is Tailscale's word for the network,
not the old product name.

## 7. Not implemented, on purpose

The Tailscale LocalAPI. `TailscaleStatus` carries a TODO with the details:
`tailscale debug local-creds` yields a loopback port and a basic-auth token for
`GET /localapi/v0/status` (empty username, token as password, `Host:
local-tailscaled.sock`), which would avoid forking a CLI on every poll.
