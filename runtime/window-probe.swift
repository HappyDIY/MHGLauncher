import CoreGraphics
import Darwin
import Foundation

guard CommandLine.arguments.count == 2,
      let processGroup = Int32(CommandLine.arguments[1]),
      processGroup > 0 else {
  exit(2)
}

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
  exit(1)
}

for window in windows {
  guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
        getpgid(owner.int32Value) == processGroup,
        (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
        (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0 > 0,
        let bounds = window[kCGWindowBounds as String] as? [String: Any],
        (bounds["Width"] as? NSNumber)?.doubleValue ?? 0 >= 640,
        (bounds["Height"] as? NSNumber)?.doubleValue ?? 0 >= 360 else {
    continue
  }
  exit(0)
}

exit(1)
