// mic-probe — prints which input-capable audio devices are "running somewhere"
// once per second (state changes + 10 s heartbeats) for 120 s.
// Purpose: determine whether macOS dictation activates the DEFAULT input
// device or some other/private device path.

import CoreAudio
import Foundation

let systemObject = AudioObjectID(kAudioObjectSystemObject)

func addr(_ sel: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal,
                               mElement: kAudioObjectPropertyElementMain)
}

func allDevices() -> [AudioObjectID] {
    var a = addr(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(systemObject, &a, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(systemObject, &a, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

func stringProp(_ dev: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String {
    var a = addr(sel)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(dev, &a, 0, nil, &size) == noErr, size > 0 else { return "?" }
    var cf: CFString = "" as CFString
    let status = withUnsafeMutablePointer(to: &cf) { p in
        AudioObjectGetPropertyData(dev, &a, 0, nil, &size, p)
    }
    guard status == noErr else { return "?" }
    return cf as String
}

func isRunningSomewhere(_ dev: AudioObjectID) -> Bool {
    var a = addr(kAudioDevicePropertyDeviceIsRunningSomewhere)
    var v: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr else { return false }
    return v != 0
}

func hasInputStreams(_ dev: AudioObjectID) -> Bool {
    var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                       mScope: kAudioObjectPropertyScopeInput,
                                       mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(dev, &a, 0, nil, &size) == noErr else { return false }
    return size > 0
}

var defaultInput = AudioObjectID(0)
do {
    var a = addr(kAudioHardwarePropertyDefaultInputDevice)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    _ = AudioObjectGetPropertyData(systemObject, &a, 0, nil, &size, &defaultInput)
}
print("default input device id: \(defaultInput)")

let inputDevices = allDevices().filter { hasInputStreams($0) }
let labels = inputDevices.map { "\($0)='\(stringProp($0, kAudioObjectPropertyName))'" }
print("input-capable devices: \(labels.joined(separator: ", "))")

let df = DateFormatter()
df.dateFormat = "HH:mm:ss"

var lastBody = ""
for tick in 0..<300 {
    let body = inputDevices.map { "\($0)=\(isRunningSomewhere($0) ? 1 : 0)" }.joined(separator: " ")
    if body != lastBody || tick % 10 == 0 {
        print("\(df.string(from: Date()))  \(body)")
        fflush(stdout)
    }
    lastBody = body
    sleep(1)
}
print("probe done")
