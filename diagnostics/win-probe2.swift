// win-probe2 — logs every on-screen window that APPEARS or DISAPPEARS
// (unfiltered owner names; baseline ignored), 0.5 s snapshots, 300 s.
// Goal: catch the dictation overlay whatever process owns it.

import CoreGraphics
import Foundation

let df = DateFormatter()
df.dateFormat = "HH:mm:ss.SSS"

func onScreenWindows() -> [Int: String] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [:] }
    var out: [Int: String] = [:]
    for w in list {
        guard let num = w[kCGWindowNumber as String] as? Int else { continue }
        let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
        let name = w[kCGWindowName as String] as? String ?? ""
        let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        out[num] = "\(owner) | '\(name)' | layer=\(layer) | \(bounds)"
    }
    return out
}

var prev = onScreenWindows()
print("baseline: \(prev.count) on-screen windows")
fflush(stdout)

for _ in 0..<600 {
    usleep(500_000)
    let now = onScreenWindows()
    for num in now.keys where prev[num] == nil {
        print("\(df.string(from: Date()))  WIN+ #\(num) \(now[num]!)")
    }
    for num in prev.keys where now[num] == nil {
        print("\(df.string(from: Date()))  WIN- #\(num) \(prev[num]!)")
    }
    if now != prev { fflush(stdout) }
    prev = now
}
print("win-probe2 done")
