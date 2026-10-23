// win-probe — logs on-screen windows owned by dictation/speech processes
// appearing and disappearing (0.5 s snapshots, 300 s window). The dictation
// mic overlay should show up as a DictationIM window while dictating.

import CoreGraphics
import Foundation

let df = DateFormatter()
df.dateFormat = "HH:mm:ss.SSS"

var prev = Set<String>()
for _ in 0..<600 {
    usleep(500_000)
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { continue }
    var now = Set<String>()
    for w in list {
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        let lo = owner.lowercased()
        if lo.contains("dictation") || lo.contains("speech") || lo.contains("siri") {
            let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
            now.insert("\(owner) \(bounds)")
        }
    }
    for a in now.subtracting(prev).sorted() { print("\(df.string(from: Date()))  WIN + \(a)") }
    for r in prev.subtracting(now).sorted() { print("\(df.string(from: Date()))  WIN - \(r)") }
    if now != prev { fflush(stdout) }
    prev = now
}
print("window probe done")
