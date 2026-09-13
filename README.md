# Strata

A minimal native macOS menu-bar clipboard history. Layers of what you copied,
newest on top.

Press **⇧⌘V**, a list appears; type to filter, ↑↓ to move, ⏎ pastes into the
app you were in, ⎋ closes. Press ⇧⌘V again while it is open to step down the
list. The menu bar item lists the last ten for the mouse. Text only.

## Requirements

- macOS 14 (Sonoma) or later
- Accessibility permission, for Strata to send ⌘V on your behalf. Without it
  the pick still lands on the pasteboard and you paste yourself.
- Quit Flycut (or any other app bound to ⇧⌘V) — Carbon lets only one process
  own a hotkey and Strata will log the failure rather than fight.

## Build

```sh
./scripts/build-app.sh      # → /Applications/Strata.app, signed, icon regenerated
```

Needs `xcodegen` and `../housekit` (icon + menu bar plate + launch-at-login).
Signing uses the stable Apple Development identity from `project.yml` for the
same reason Tessellate does: TCC ties the Accessibility grant to the code
signature, and an ad-hoc build loses it on every rebuild.

## Privacy

- Copies marked `org.nspasteboard.ConcealedType` / `TransientType` (what
  password managers set) are never recorded.
- Apps in the ignore list (1Password and Keychain Access by default) are skipped.
- History lives in `~/Library/Application Support/Strata/clippings.json`, local only.

## URL scheme

`strata://show` opens the picker, `strata://settings` the settings window.

## Architecture

| | |
| --- | --- |
| `Clipboard/PasteboardWatcher` | Polls `changeCount` every 300 ms — there is no notification API |
| `Clipboard/Paster` | Writes the pasteboard, then a `CGEvent` ⌘V if Accessibility allows |
| `Picker/PickerPanel` | Non-activating floating `NSPanel`, so the target app keeps focus |
| `Hotkeys/*` | Carbon `RegisterEventHotKey`; `ShortcutDisplay` / `ShortcutRecorder` are Tessellate's, verbatim |
| `Storage/ClippingStore` | Newest-first, de-duplicated, capped; JSON file + `UserDefaults` settings |
| `Settings/*` | SwiftUI grouped form in an `NSWindow` |
