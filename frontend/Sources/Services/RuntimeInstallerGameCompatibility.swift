import Foundation

extension RuntimeInstaller {
    func gameRuntimeSupportsWindowsUI(_ runtime: InstalledRuntime) -> Bool {
        let wine = runtime.gameRuntimeURL.appending(path: "wine")
        let fontEngine = wine.appending(path: "lib/libfreetype.6.dylib")
        let console = wine.appending(path: "lib/wine/x86_64-windows/wineconsole.exe")
        let preferences = wine.appending(path: "lib/wine/x86_64-windows/winecfg.exe")
        return fileManager.fileExists(atPath: fontEngine.path)
            && fileManager.fileExists(atPath: console.path)
            && fileManager.fileExists(atPath: preferences.path)
    }
}
