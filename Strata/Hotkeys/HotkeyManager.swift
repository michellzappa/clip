import AppKit
import Carbon

/// One global hotkey through Carbon's `RegisterEventHotKey`. Reduced from
/// Tessellate's manager: no event tap, since Strata needs only the activation
/// key and the picker panel handles the rest as a key window.
@MainActor
final class HotkeyManager {
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x5354_5241 // "STRA"
    var onActivation: () -> Void = {}

    func start() {
        installEventHandler()
    }

    func register(_ binding: CommandBinding?) {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        guard let binding else {
            NSLog("Strata: hotkey is unbound")
            return
        }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(binding.keyCode),
            UInt32(binding.modifiers),
            EventHotKeyID(signature: Self.signature, id: 1),
            // Must match the target the handler is installed on.
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotkeyRef = ref
        } else {
            NSLog("Strata: hotkey failed to register status=\(status) (in use by another app?)")
        }
    }

    private func installEventHandler() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in manager.onActivation() }
                return noErr
            },
            1,
            &spec,
            selfPtr,
            &eventHandler
        )
    }

    /// The manager lives as long as the app; unregister explicitly if that changes.
    func stop() {
        if let ref = hotkeyRef { UnregisterEventHotKey(ref) }
        if let handler = eventHandler { RemoveEventHandler(handler) }
        hotkeyRef = nil
        eventHandler = nil
    }
}
