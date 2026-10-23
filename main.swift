// dictation-pause — pauses media while macOS built-in dictation is active,
// and resumes it when dictation ends. Event-driven: CoreAudio listeners only,
// no polling, no spawned processes.

import AppKit
import ApplicationServices
import CoreAudio
import Darwin
import Dispatch

// MARK: - Config

let logPath = "/tmp/dictation-pause.log"
let maxLogBytes = 100_000

// After mic activation: two output-activity samples, 0.35 s apart. Pause fires
// only if BOTH sample "running" — the gap skips the short dictation start
// beep, so a merely *paused* video can never be toggled back ON.
let sample1Delay = 0.35
let sample2Delay = 0.25

// Process-name fragments (lowercase) that indicate macOS dictation owns the mic.
let dictationFragments = ["speechrecogn", "dictation"]
// Fragments logged for tuning when the mic activates without a dictation match.
let diagnosticFragments = ["speech", "dictat", "recogn", "siri", "assistant", "voice", "keyboard"]

// MARK: - Logging

func log(_ message: String) {
    let line = "\(Date()) \(message)\n"
    if let data = line.data(using: .utf8) {
        let url = URL(fileURLWithPath: logPath)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: url)
        }
    }
    // Rotation guard: start a fresh log instead of growing forever.
    if let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
       let size = attrs[.size] as? UInt64, size > UInt64(maxLogBytes) {
        try? FileManager.default.removeItem(atPath: logPath)
    }
}

// MARK: - Media key

// NX_KEYTYPE_PLAY from IOKit's ev_keymap.h (not exposed to Swift).
let nxKeyTypePlay = 16
let nxSubtypeAuxControlButtons: Int16 = 8

func postMediaKeyToggle() {
    for keyDown in [true, false] {
        let data1 = (nxKeyTypePlay << 16) | ((keyDown ? 0x0A : 0x0B) << 8)
        let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [],
                                       timestamp: 0, windowNumber: 0, context: nil,
                                       subtype: nxSubtypeAuxControlButtons,
                                       data1: data1, data2: -1)
        guard let cgEvent = event?.cgEvent else {
            log("ERROR: could not construct media-key event")
            return
        }
        cgEvent.post(tap: .cghidEventTap)
    }
    log("media-key toggle posted")
}

// MARK: - CoreAudio helpers

let systemObject = AudioObjectID(kAudioObjectSystemObject)

func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                               mElement: kAudioObjectPropertyElementMain)
}

func defaultDeviceID(_ selector: AudioObjectPropertySelector) -> AudioObjectID {
    var device = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var addr = propertyAddress(selector)
    guard AudioObjectGetPropertyData(systemObject, &addr, 0, nil, &size, &device) == noErr else { return 0 }
    return device
}

func deviceIsRunningSomewhere(_ device: AudioObjectID) -> Bool {
    guard device != 0 else { return false }
    var running: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    var addr = propertyAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running) == noErr else { return false }
    return running != 0
}

// MARK: - Process gate

func runningProcessNames() -> [String] {
    let count = Int(proc_listallpids(nil, 0))
    guard count > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: count + 64) // slack for processes spawning meanwhile
    let written = proc_listallpids(&pids, Int32(pids.count))
    guard written > 0 else { return [] }
    var names = Set<String>()
    for pid in pids.prefix(Int(written)) where pid > 0 {
        var path = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
            names.insert(String(cString: path).split(separator: "/").last.map(String.init) ?? "")
        } else {
            var name = [CChar](repeating: 0, count: 64)
            if proc_name(pid, &name, UInt32(name.count)) > 0 {
                names.insert(String(cString: name))
            }
        }
    }
    return names.filter { !$0.isEmpty }.sorted()
}

func isDictationProcessPresent() -> Bool {
    let names = runningProcessNames()
    let pairs = names.map { ($0, $0.lowercased()) }
    let matches = pairs.filter { _, lo in dictationFragments.contains { lo.contains($0) } }.map { $0.0 }
    if !matches.isEmpty {
        log("dictation process present: \(matches.joined(separator: ", "))")
        return true
    }
    let interesting = pairs
        .filter { _, lo in diagnosticFragments.contains { lo.contains($0) } }
        .map { $0.0 }
    log("no dictation process; mic likely belongs to another app (speech-ish: [\(interesting.joined(separator: ", "))])")
    return false
}

// MARK: - State machine (all state touched on the main queue only)

var watchedInput = AudioObjectID(0)
var micRunningObserved = false
var pausedByUs = false
var cycleID = 0

let listenerQueue = DispatchQueue(label: "com.dts.dictation-pause.audio")

func handleMicStateChange() {
    let running = deviceIsRunningSomewhere(watchedInput)
    guard running != micRunningObserved else { return }
    micRunningObserved = running
    cycleID += 1 // invalidate any in-flight pause decision
    if running {
        log("mic: ACTIVE")
        schedulePauseDecision()
    } else {
        log("mic: idle")
        if pausedByUs {
            pausedByUs = false
            log("dictation ended → resuming playback")
            postMediaKeyToggle()
        }
    }
}

func schedulePauseDecision() {
    cycleID += 1
    let id = cycleID
    DispatchQueue.main.asyncAfter(deadline: .now() + sample1Delay) {
        guard id == cycleID, micRunningObserved else { return }
        guard isDictationProcessPresent() else { return }
        let first = deviceIsRunningSomewhere(defaultDeviceID(kAudioHardwarePropertyDefaultOutputDevice))
        DispatchQueue.main.asyncAfter(deadline: .now() + sample2Delay) {
            guard id == cycleID, micRunningObserved else { return }
            let second = deviceIsRunningSomewhere(defaultDeviceID(kAudioHardwarePropertyDefaultOutputDevice))
            if first && second {
                if !pausedByUs {
                    pausedByUs = true
                    log("dictation active + audio playing → pausing")
                    postMediaKeyToggle()
                }
            } else {
                log("output idle → nothing to pause")
            }
        }
    }
}

// Watchdog: CoreAudio change-notifications can silently stop being delivered
// (e.g. if coreaudiod restarts). A cheap 5 s property read re-syncs state, so
// a missed edge is recovered and logged instead of silently ignored.
func reconcileWithWatchdog() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { reconcileWithWatchdog() }
    guard watchedInput != 0 else { return }
    let running = deviceIsRunningSomewhere(watchedInput)
    guard running != micRunningObserved else { return }
    log("watchdog: mic \(running ? "ACTIVE" : "idle") missed by listener — recovering")
    handleMicStateChange()
}

// MARK: - Device watching

var inputListenerBlock: AudioObjectPropertyListenerBlock?

func watch(inputDevice: AudioObjectID) {
    if watchedInput != 0, let block = inputListenerBlock {
        var addr = propertyAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
        AudioObjectRemovePropertyListenerBlock(watchedInput, &addr, listenerQueue, block)
    }
    watchedInput = inputDevice
    guard inputDevice != 0 else {
        log("no default input device; waiting for one")
        return
    }
    let block: AudioObjectPropertyListenerBlock = { _, _ in
        DispatchQueue.main.async { handleMicStateChange() }
    }
    inputListenerBlock = block
    var addr = propertyAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
    let status = AudioObjectAddPropertyListenerBlock(inputDevice, &addr, listenerQueue, block)
    log("watching input device \(inputDevice) (status \(status))")
}

let defaultInputChanged: AudioObjectPropertyListenerBlock = { _, _ in
    DispatchQueue.main.async {
        let device = defaultDeviceID(kAudioHardwarePropertyDefaultInputDevice)
        log("default input changed → device \(device)")
        watch(inputDevice: device)
        micRunningObserved = deviceIsRunningSomewhere(device) // resync without acting on an edge
        cycleID += 1
    }
}

// MARK: - Main

log("--- dictation-pause starting (pid \(getpid())) ---")
if AXIsProcessTrusted() {
    log("accessibility: trusted")
} else {
    log("WARNING: Accessibility not granted — media-key events will be dropped by the system")
}

var sysAddr = propertyAddress(kAudioHardwarePropertyDefaultInputDevice)
AudioObjectAddPropertyListenerBlock(systemObject, &sysAddr, listenerQueue, defaultInputChanged)

watch(inputDevice: defaultDeviceID(kAudioHardwarePropertyDefaultInputDevice))
micRunningObserved = deviceIsRunningSomewhere(watchedInput)
log("initial mic state: \(micRunningObserved ? "active" : "idle"); acting on changes only")
reconcileWithWatchdog()

dispatchMain()
