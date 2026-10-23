// correlate2-probe — samples at 200 ms for 300 s, logging edges of:
//   mic indicator (Window Server 'StatusIndicator' windows on screen)
//   localspeechrecognition process presence
//   default output "running somewhere"
// Goal: measure which speech-daemon churn edge aligns with indicator up/down.

import CoreAudio
import CoreGraphics
import Foundation

let systemObject = AudioObjectID(kAudioObjectSystemObject)

func defaultOutput() -> AudioObjectID {
    var dev = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                       mScope: kAudioObjectPropertyScopeGlobal,
                                       mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(systemObject, &a, 0, nil, &size, &dev) == noErr else { return 0 }
    return dev
}

func outputRunning(_ dev: AudioObjectID) -> Bool {
    guard dev != 0 else { return false }
    var v: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                       mScope: kAudioObjectPropertyScopeGlobal,
                                       mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr else { return false }
    return v != 0
}

func micIndicatorUp() -> Bool {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
    return list.contains {
        ($0[kCGWindowOwnerName as String] as? String) == "Window Server"
            && ($0[kCGWindowName as String] as? String) == "StatusIndicator"
    }
}

func speechProcPresent() -> Bool {
    let count = Int(proc_listallpids(nil, 0))
    guard count > 0 else { return false }
    var pids = [pid_t](repeating: 0, count: count + 64)
    let written = proc_listallpids(&pids, Int32(pids.count))
    guard written > 0 else { return false }
    for pid in pids.prefix(Int(written)) where pid > 0 {
        var path = [CChar](repeating: 0, count: 4096)
        let name: String
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
            name = String(cString: path).split(separator: "/").last.map(String.init) ?? ""
        } else {
            var n = [CChar](repeating: 0, count: 64)
            proc_name(pid, &n, UInt32(n.count))
            name = String(cString: n)
        }
        if name == "localspeechrecognition" { return true }
    }
    return false
}

let df = DateFormatter()
df.dateFormat = "HH:mm:ss.SSS"
let output = defaultOutput()

var prevInd = false
var prevSpeech = true
var prevOut = false
for tick in 0..<1500 {
    let ind = micIndicatorUp()
    let speech = speechProcPresent()
    let out = outputRunning(output)
    if ind != prevInd || speech != prevSpeech || out != prevOut || tick % 50 == 0 {
        print("\(df.string(from: Date()))  indicator=\(ind ? 1 : 0) speech=\(speech ? 1 : 0) output=\(out ? 1 : 0)")
        fflush(stdout)
    }
    prevInd = ind
    prevSpeech = speech
    prevOut = out
    usleep(200_000)
}
print("correlate2 done")
