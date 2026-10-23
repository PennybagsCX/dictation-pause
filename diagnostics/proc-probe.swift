// proc-probe — logs dictation/speech-related processes appearing and
// disappearing (0.5 s snapshots, 300 s window) to find a reliable signal
// that macOS dictation is active (audio-device flags stay silent).

import Foundation

let fragments = ["dict", "speech", "recogn", "siri", "assistan", "voice", "shortcut", "keyboard"]

func snapshot() -> Set<String> {
    let count = Int(proc_listallpids(nil, 0))
    guard count > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: count + 64)
    let written = proc_listallpids(&pids, Int32(pids.count))
    guard written > 0 else { return [] }
    var out = Set<String>()
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
        let lo = name.lowercased()
        if fragments.contains(where: { lo.contains($0) }) {
            out.insert("\(pid):\(name)")
        }
    }
    return out
}

let df = DateFormatter()
df.dateFormat = "HH:mm:ss"

var prev = snapshot()
print("baseline (\(prev.count)):")
for p in prev.sorted() { print("  \(p)") }
fflush(stdout)

for _ in 0..<600 {
    usleep(500_000)
    let now = snapshot()
    for a in now.subtracting(prev).sorted() { print("\(df.string(from: Date()))  + \(a)") }
    for r in prev.subtracting(now).sorted() { print("\(df.string(from: Date()))  - \(r)") }
    prev = now
}
print("probe done")
