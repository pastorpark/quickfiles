import AppKit
import Carbon

final class HotKeyController {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var currentDefinition: HotKeyDefinition = .defaultValue
    private var lastFireDate = Date.distantPast
    private let signature = OSType("QFLS".fourCharCodeValue)
    private let hotKeyID = UInt32(1)
    var onPressed: (() -> Void)?

    static func canRegister(_ definition: HotKeyDefinition) -> Bool {
        var hotKeyRef: EventHotKeyRef?
        let hotKey = EventHotKeyID(signature: OSType("QFTS".fourCharCodeValue), id: UInt32(999))
        let status = RegisterEventHotKey(
            definition.keyCode,
            definition.modifierFlags,
            hotKey,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        return status == noErr
    }

    func register(_ definition: HotKeyDefinition = .defaultValue) {
        unregister()
        currentDefinition = definition
        if !installCarbonHotKey(definition) {
            installEventMonitors(definition)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func installCarbonHotKey(_ definition: HotKeyDefinition) -> Bool {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard hotKeyID.signature == OSType("QFLS".fourCharCodeValue),
                      let userData else {
                    return noErr
                }

                let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    controller.fire()
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )

        guard handlerStatus == noErr else {
            NSLog("QuickFiles hotkey handler install failed: \(handlerStatus)")
            return false
        }

        let hotKey = EventHotKeyID(signature: signature, id: hotKeyID)
        let registerStatus = RegisterEventHotKey(
            definition.keyCode,
            definition.modifierFlags,
            hotKey,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus != noErr {
            NSLog("QuickFiles Carbon hotkey registration failed: \(registerStatus)")
            if let eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
            return false
        }
        return true
    }

    private func installEventMonitors(_ definition: HotKeyDefinition) {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.matches(event, definition: definition) else { return }
            DispatchQueue.main.async {
                self.fire()
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.matches(event, definition: definition) else { return event }
            self.fire()
            return nil
        }
    }

    private func matches(_ event: NSEvent, definition: HotKeyDefinition) -> Bool {
        guard event.keyCode == UInt16(definition.keyCode) else { return false }
        let relevantFlags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        return event.modifierFlags.intersection(relevantFlags) == eventModifiers(for: definition.modifierFlags)
    }

    private func eventModifiers(for carbonFlags: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonFlags & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonFlags & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonFlags & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonFlags & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    private func fire() {
        let now = Date()
        guard now.timeIntervalSince(lastFireDate) > 0.25 else { return }
        lastFireDate = now
        onPressed?()
    }

    deinit {
        unregister()
    }
}

private extension String {
    var fourCharCodeValue: FourCharCode {
        var result: FourCharCode = 0
        for scalar in unicodeScalars {
            result = (result << 8) + FourCharCode(scalar.value)
        }
        return result
    }
}
