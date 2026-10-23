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

// Pause ONLY on stable pre-dictation playback: the output device must have
// been rendering continuously for the last few polls. Chromium keeps a
// paused tab's audio stream open (rendering silence) for a while, so a tab
// paused moments before dictating can still read "running" — an unavoidable
// limitation without per-app audio metering. There is deliberately NO
// post-start sampling: a wrong toggle here RESUMES a paused tab (worse than
// missing a pause), and post-start samples can't be trusted (start beep,
// lingering streams).
let stablePlaybackTicks = 2

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
var consecutiveRunning = 0

func pollTick() {
    DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) { pollTick() }
    let running = deviceIsRunningSomewhere(defaultOutputDeviceID())
    if running {
        consecutiveRunning += 1
    } else {
        consecutiveRunning = 0
    }
    let up = micIndicatorUp()
    if up != micActiveObserved {
        if up {
            micActiveObserved = true
            downStreak = 0
            log("mic indicator UP")
            if consecutiveRunning >= stablePlaybackTicks {
                if !pausedByUs {
                    pausedByUs = true
                    log("playback confirmed stable → pausing now")
                    postMediaKeyToggle()
                }
            } else {
                log("no stable playback before mic activity → not pausing")
            }
        } else {
            downStreak += 1
            if downStreak >= downConfirmSamples {
                micActiveObserved = false
                downStreak = 0
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
