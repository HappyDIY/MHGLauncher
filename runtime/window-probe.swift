import CoreGraphics
import Darwin
import Foundation

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
  exit(1)
}

func isVisibleGameSize(_ window: [String: Any]) -> Bool {
  guard (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
        (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0 > 0,
        let bounds = window[kCGWindowBounds as String] as? [String: Any] else { return false }
  return (bounds["Width"] as? NSNumber)?.doubleValue ?? 0 >= 640 &&
         (bounds["Height"] as? NSNumber)?.doubleValue ?? 0 >= 360
}

func gameProcessIDs() -> Set<pid_t> {
  let capacity = max(proc_listallpids(nil, 0), 0)
  guard capacity > 0 else { return [] }
  var pids = [pid_t](repeating: 0, count: Int(capacity))
  let bytes = Int32(pids.count * MemoryLayout<pid_t>.stride)
  let count = max(proc_listallpids(&pids, bytes), 0)
  var matches = Set<pid_t>()
  for pid in pids.prefix(Int(count)) where pid > 0 {
    var name = [CChar](repeating: 0, count: 256)
    guard proc_name(pid, &name, UInt32(name.count)) > 0 else { continue }
    let value = String(cString: name).lowercased()
    if value == "yuanshen.exe" || value == "genshinimpact.exe" { matches.insert(pid) }
  }
  return matches
}

if CommandLine.arguments == [CommandLine.arguments[0], "--snapshot"] {
  for window in windows where isVisibleGameSize(window) {
    if let number = window[kCGWindowNumber as String] as? NSNumber { print(number.intValue) }
  }
  for pid in gameProcessIDs() { print("p:\(pid)") }
  exit(0)
}

guard CommandLine.arguments.count == 3,
      let processGroup = Int32(CommandLine.arguments[1]), processGroup > 0 else { exit(2) }
let snapshot = CommandLine.arguments[2].split(separator: ",")
let baseline = Set(snapshot.compactMap { Int($0) })
let baselineProcesses = Set(snapshot.compactMap { value -> pid_t? in
  guard value.hasPrefix("p:") else { return nil }
  return pid_t(value.dropFirst(2))
})

for window in windows where isVisibleGameSize(window) {
  guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
        let number = window[kCGWindowNumber as String] as? NSNumber else { continue }
  let ownerName = (window[kCGWindowOwnerName as String] as? String ?? "").lowercased()
  let isGameWindow = ownerName.contains("yuanshen") || ownerName.contains("genshin") || ownerName.contains("wine")
  let isNewWindow = !baseline.contains(number.intValue)
  guard getpgid(owner.int32Value) == processGroup || isGameWindow || isNewWindow else { continue }
  exit(0)
}

// 进程已创建但窗口尚未出现，使用独立状态避免提前解除一次性网络门控。
if !gameProcessIDs().subtracting(baselineProcesses).isEmpty { exit(3) }

exit(1)
