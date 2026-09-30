import AppKit
import SwiftUI

final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@available(macOS 14.2, *)
final class DragHostingView: NSHostingView<PetView> {
    var onDragEnded: (() -> Void)?
    var companionMenu: NSMenu?
    override func rightMouseDown(with event: NSEvent) {
        if let companionMenu { NSMenu.popUpContextMenu(companionMenu, with: event, for: self) }
    }
    private var dragOrigin: NSPoint?
    private var windowOrigin: NSPoint?
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func mouseDown(with event: NSEvent) {
        dragOrigin = window?.convertPoint(toScreen: event.locationInWindow)
        windowOrigin = window?.frame.origin
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragOrigin, let origin = windowOrigin else { return }
        guard let location = window?.convertPoint(toScreen: event.locationInWindow) else { return }
        window?.setFrameOrigin(NSPoint(x: origin.x + location.x - start.x, y: origin.y + location.y - start.y))
    }
    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil; windowOrigin = nil
        onDragEnded?()
    }
}

@available(macOS 14.2, *)
final class DesktopCompanion {
    let panel: DesktopPanel
    private var screenObserver: NSObjectProtocol?
    var contextMenu: NSMenu? {
        didSet { (panel.contentView as? DragHostingView)?.companionMenu = contextMenu }
    }

    init(model: CompanionModel) {
        panel = DesktopPanel(contentRect: NSRect(origin: .zero,size: PetView.desktopSize),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Miho 迷糊"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let content = DragHostingView(rootView: PetView(model: model))
        content.onDragEnded = { [weak self] in self?.clampAndSave() }
        panel.contentView = content
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "petX") != nil {
            panel.setFrameOrigin(NSPoint(x: defaults.double(forKey: "petX"), y: defaults.double(forKey: "petY")))
        } else if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - PetView.desktopSize.width - 24, y: screen.visibleFrame.minY + 12))
        }
        clampAndSave()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.clampAndSave()
        }
        panel.orderFrontRegardless()
    }

    func setVisible(_ value: Bool) {
        if value { clampAndSave(); panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }

    func clampAndSave() {
        let frame = panel.frame
        let screen = NSScreen.screens.max { lhs, rhs in
            let a = lhs.visibleFrame.intersection(frame)
            let b = rhs.visibleFrame.intersection(frame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(x: min(max(frame.minX, visible.minX), visible.maxX - frame.width),
                             y: min(max(frame.minY, visible.minY), visible.maxY - frame.height))
        panel.setFrameOrigin(origin)
        UserDefaults.standard.set(origin.x, forKey: "petX")
        UserDefaults.standard.set(origin.y, forKey: "petY")
    }

    func dispose() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        panel.close()
    }
}
