import Cocoa
import Carbon

class HotkeyMonitor {
    private var eventTap: CFMachPort?
    
    func start() {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (_, _, event, _) -> Unmanaged<CGEvent>? in
                let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                if keycode == 0x62 { // F7 key
                    print("F7_PRESSED")
                    fflush(stdout)
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: nil)
        
        if let eventTap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            CFRunLoopRun()
        }
    }
}

let monitor = HotkeyMonitor()
monitor.start()
