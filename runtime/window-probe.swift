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

if CommandLine.arguments == [CommandLine.arguments[0], "--snapshot"] {
  for window in windows where isVisibleGameSize(window) {
    if let number = window[kCGWindowNumber as String] as? NSNumber { print(number.intValue) }
  }
  exit(0)
}

guard CommandLine.arguments.count == 3,
      let processGroup = Int32(CommandLine.arguments[1]), processGroup > 0 else { exit(2) }
let baseline = Set(CommandLine.arguments[2].split(separator: ",").compactMap { Int($0) })

for window in windows where isVisibleGameSize(window) {
  guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
        let number = window[kCGWindowNumber as String] as? NSNumber else { continue }
  let ownerName = (window[kCGWindowOwnerName as String] as? String ?? "").lowercased()
  let isGameWindow = ownerName.contains("yuanshen") || ownerName.contains("genshin") || ownerName.contains("wine")
  let isNewWindow = !baseline.contains(number.intValue)
  guard getpgid(owner.int32Value) == processGroup || isGameWindow || isNewWindow else { continue }
  exit(0)
}

exit(1)
