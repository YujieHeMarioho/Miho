import AppKit

if #available(macOS 14.2, *) {
    let app = NSApplication.shared
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
