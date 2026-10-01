import AppKit
import MihoDesktop

if #available(macOS 14.2, *) {
    let app = NSApplication.shared
    if let index = CommandLine.arguments.firstIndex(of: "--analyze-file"), CommandLine.arguments.indices.contains(index+1) {
        do { try AudioFileProbe.run(url: URL(fileURLWithPath: CommandLine.arguments[index+1]));exit(0) }
        catch { fputs("Miho audio probe: \(error.localizedDescription)\n",stderr);exit(1) }
    }
    let motionExport = CommandLine.arguments.contains("--export-motion")
    if let index = CommandLine.arguments.firstIndex(of: motionExport ? "--export-motion" : "--export-artifacts"),
       CommandLine.arguments.indices.contains(index + 1) {
        do {
            try MainActor.assumeIsolated {
                let url = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: !motionExport)
                if motionExport { try ArtworkExport.writeMotion(to: url) } else { try ArtworkExport.write(to: url) }
            }
            exit(0)
        } catch {
            fputs("Miho artwork: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
    withExtendedLifetime(delegate) {}
} else {
    let alert = NSAlert()
    alert.messageText = "Miho 需要 macOS 14.2 或更新版本"
    alert.runModal()
    exit(1)
}
