import Carbon

final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var pressed = false
    private var pressedAt = Date.distantPast
    private let identifier: UInt32
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    init(identifier: UInt32 = 1) throws {
        self.identifier = identifier
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x5153454C, identifier.id == owner.identifier else {
                return OSStatus(eventNotHandledErr)
            }
            if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                guard owner.pressed else { return noErr }
                owner.pressed = false
                owner.onRelease?()
            } else if !owner.pressed || Date().timeIntervalSince(owner.pressedAt) > 2 {
                // A lost release event must not block the shortcut for good.
                owner.pressed = true
                owner.pressedAt = Date()
                owner.onPress?()
            }
            return noErr
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { throw HotKeyError.registration(result) }
    }

    // Keep the old binding if the new one is unavailable.
    func register(_ shortcut: Shortcut) throws {
        try register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
    }

    /// Releases the keys, for example while a new shortcut is being recorded.
    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        pressed = false
    }

    func register(keyCode: UInt32, modifiers: UInt32) throws {
        var replacement: EventHotKeyRef?
        let result = RegisterEventHotKey(keyCode, modifiers,
            EventHotKeyID(signature: 0x5153454C, id: identifier), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &replacement)
        guard result == noErr else { throw HotKeyError.registration(result) }
        if let reference { UnregisterEventHotKey(reference) }
        reference = replacement
        pressed = false
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}

enum HotKeyError: Error { case registration(OSStatus) }
