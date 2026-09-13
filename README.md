# Clip

A minimal native macOS menu-bar clipboard history. Layers of what you copied,
newest on top.

Press **⇧⌘V**, a list appears; type to filter, ↑↓ to move, ⏎ pastes into the
app you were in, ⎋ closes. Press ⇧⌘V again while it is open to step down the
list. The menu bar item lists the last ten for the mouse. Text only.

## Requirements

- macOS 14 (Sonoma) or later
- Accessibility permission, for Clip to send ⌘V on your behalf. Without it
  the pick still lands on the pasteboard and you paste yourself.
- Quit Flycut (or any other app bound to ⇧⌘V) — Carbon lets only one process
  own a hotkey and Clip will log the failure rather than fight.

## Build

```sh
./scripts/build-app.sh      # → /Applications/Clip.app, signed, icon regenerated
```

Needs `xcodegen` and the sibling [`../housekit`](../housekit) package, which
supplies the menu bar plate, the app icon, the settings window chrome and
launch-at-login — the pieces Clip shares with Tessellate and Cargo. To work
in Xcode instead: `xcodegen generate && open Clip.xcodeproj`.

Signing uses the stable Apple Development identity from `project.yml` for the
same reason Tessellate does: TCC ties the Accessibility grant to the code
signature, and an ad-hoc build loses it on every rebuild. Set your own
`DEVELOPMENT_TEAM` first.

### Downloadable releases

Push a tag matching `CFBundleShortVersionString` (e.g. `v0.1.0`) to run
`.github/workflows/release.yml`: universal build, Developer ID signature,
notarization, a ZIP plus `SHA256SUMS` on the GitHub Release. Same secrets as
Tessellate's workflow (`APPLE_TEAM_ID`, the Developer ID certificate, an App
Store Connect API key).

## Privacy

- Copies marked `org.nspasteboard.ConcealedType` / `TransientType` (what
  password managers set) are never recorded.
- Apps in the ignore list (1Password and Keychain Access by default) are skipped.
- History lives in `~/Library/Application Support/Clip/clippings.json`, local only.

## URL scheme

`clip://show` opens the picker, `clip://settings` the settings window.

## Configuration

Settings lives in the menu bar item (⌘,): **History** (shortcut, how many
to keep, how many in the menu, ignored apps) · **General** (launch at login,
menu bar icon, Accessibility status) · **About**.

## Architecture

AppKit throughout, no SwiftUI, no dependencies beyond `HouseKit`.

| | |
| --- | --- |
| `Clipboard/PasteboardWatcher` | Polls `changeCount` every 300 ms — there is no notification API |
| `Clipboard/Paster` | Writes the pasteboard, then a `CGEvent` ⌘V if Accessibility allows |
| `Picker/PickerPanel` | Non-activating floating `NSPanel`, so the target app keeps focus |
| `HouseKit.GlobalHotkey` / `ShortcutRecorder` | Carbon `RegisterEventHotKey` and the shortcut control, shared with Tessellate |
| `Storage/ClippingStore` | Newest-first, de-duplicated, capped; JSON file + `UserDefaults` settings |
| `Settings/HistoryPage` | Clip's page in the HouseKit settings window, next to the shared General and About pages |
| `App/ClipApp` | `NSStatusItem` and its menu — header, recent clippings, then the house tail (Settings, Launch at Login, Quit) |
