import Carbon

final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var pressed = false
    private let identifier: UInt32
    var action: (() -> Void)?

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
                owner.pressed = false
            } else if !owner.pressed {
                owner.pressed = true
                owner.action?()
            }
            return noErr
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { throw HotKeyError.registration(result) }
    }

    // Keep the old binding if the new one is unavailable.
    func register(testShortcut: Bool) throws {
        let modifiers = UInt32(optionKey) | (testShortcut ? UInt32(shiftKey) : 0)
        try register(keyCode: UInt32(kVK_Escape), modifiers: modifiers)
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

enum OCRShortcut: Int, CaseIterable {
    case controlEscape, controlShiftEscape
    var title: String {
        self == .controlEscape ? "Control + Esc" : "Control + Shift + Esc"
    }
    var keyCode: UInt32 { UInt32(kVK_Escape) }
    var modifiers: UInt32 {
        UInt32(controlKey) | (self == .controlShiftEscape ? UInt32(shiftKey) : 0)
    }
}
