// dictation-pause v2 — pauses media playback while the system microphone
// indicator is up, and resumes when it clears.
//
// Why window polling instead of CoreAudio device watching: on recent macOS,
// dictation captures the mic through a path that never raises the input
// device's IsRunningSomewhere flag (verified empirically — see
// diagnostics/). The system mic indicator windows (owner "Window Server",
// name "StatusIndicator") ARE raised for microphone activity, so we poll
// CGWindowList at 2 Hz (~0.1% CPU).

import AppKit
import ApplicationServices
import CoreAudio
import Darwin
import Dispatch

// MARK: - Config

let logPath = "/tmp/dictation-pause.log"
let maxLogBytes = 100_000
let pollInterval = 0.25
let downConfirmSamples = 2 // indicator must be gone ~0.5 s before we resume

// Fast path: if the output device was rendering audio shortly BEFORE mic
// activity started, that evidence is trustworthy (the dictation start beep
// hasn't happened yet), so pause immediately. Fallback: two output samples
// after the start, 0.4 s apart — this skips the start beep and ensures a
// merely *paused* tab (no audio stream) is never toggled back ON.
let instantPauseRecency = 1.5
let sample1Delay = 0.4
let sample2Delay = 0.25

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

// MARK: - Mic indicator (the dictation/mic-activity signal)

func micIndicatorUp() -> Bool {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
    return list.contains {
        ($0[kCGWindowOwnerName as String] as? String) == "Window Server"
            && ($0[kCGWindowName as String] as? String) == "StatusIndicator"
    }
}

// MARK: - Output audio state

func defaultOutputDeviceID() -> AudioObjectID {
    var device = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr else { return 0 }
    return device
}

func deviceIsRunningSomewhere(_ device: AudioObjectID) -> Bool {
    guard device != 0 else { return false }
    var running: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running) == noErr else { return false }
    return running != 0
}

// MARK: - State machine (main queue only)

var micActiveObserved = false
var downStreak = 0
var pausedByUs = false
var cycleID = 0
var lastPlayingAt = Date.distantPast

func schedulePauseDecision() {
    cycleID += 1
    let id = cycleID
    DispatchQueue.main.asyncAfter(deadline: .now() + sample1Delay) {
        guard id == cycleID, micActiveObserved else { return }
        let first = deviceIsRunningSomewhere(defaultOutputDeviceID())
        DispatchQueue.main.asyncAfter(deadline: .now() + sample2Delay) {
            guard id == cycleID, micActiveObserved else { return }
            let second = deviceIsRunningSomewhere(defaultOutputDeviceID())
            if first && second {
                if !pausedByUs {
                    pausedByUs = true
                    log("mic active + audio streaming → pausing")
                    postMediaKeyToggle()
                }
            } else {
                log("mic active but no audio stream → nothing to pause")
            }
        }
    }
}

func pollTick() {
    DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) { pollTick() }
    if deviceIsRunningSomewhere(defaultOutputDeviceID()) {
        lastPlayingAt = Date()
    }
    let up = micIndicatorUp()
    if up != micActiveObserved {
        if up {
            micActiveObserved = true
            downStreak = 0
            log("mic indicator UP")
            if Date().timeIntervalSince(lastPlayingAt) < instantPauseRecency {
                if !pausedByUs {
                    pausedByUs = true
                    log("audio was playing just before mic activity → pausing now")
                    postMediaKeyToggle()
                }
            } else {
                schedulePauseDecision()
            }
        } else {
            downStreak += 1
            if downStreak >= downConfirmSamples {
                micActiveObserved = false
                downStreak = 0
                cycleID += 1 // cancel any in-flight pause decision
                log("mic indicator down")
                if pausedByUs {
                    pausedByUs = false
                    log("→ resuming playback")
                    postMediaKeyToggle()
                }
            }
        }
    } else if !up {
        downStreak = 0
    }
}

// MARK: - Main

log("--- dictation-pause v2 starting (pid \(getpid())) ---")
if AXIsProcessTrusted() {
    log("accessibility: trusted")
} else {
    log("WARNING: Accessibility not granted — media-key events will be dropped by the system")
}
log("polling system mic indicator every \(pollInterval)s")
pollTick()
dispatchMain()
