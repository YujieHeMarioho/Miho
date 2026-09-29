import AppKit
import MihoDesktop

if #available(macOS 14.2, *) {
    let app = NSApplication.shared
    if let index = CommandLine.arguments.firstIndex(of: "--export-artifacts"),
       CommandLine.arguments.indices.contains(index + 1) {
        do {
            try MainActor.assumeIsolated {
                try ArtworkExport.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
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
