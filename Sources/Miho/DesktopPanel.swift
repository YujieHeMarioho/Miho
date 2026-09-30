import AppKit
import SwiftUI

final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@available(macOS 14.2, *)
final class DragHostingView: NSHostingView<PetView> {
    var onDragEnded: (() -> Void)?
    var onRotationBegan: (() -> Void)?
    var onRotationChanged: ((Double,Double,Double) -> Void)?
    var onRotationEnded: (() -> Void)?
    var onResetRotation: (() -> Void)?
    var companionMenu: NSMenu?
    override func rightMouseDown(with event: NSEvent) {
        finishGesture()
        if let companionMenu { NSMenu.popUpContextMenu(companionMenu, with: event, for: self) }
    }
    private var dragOrigin: NSPoint?
    private var windowOrigin: NSPoint?
    private var rotating = false
    private var lastRotationPoint = NSPoint.zero
    private var lastRotationTime = 0.0
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func mouseDown(with event: NSEvent) {
        finishGesture()
        if event.clickCount == 2 {
            onResetRotation?()
        } else if event.modifierFlags.contains(.option) {
            dragOrigin = window?.convertPoint(toScreen: event.locationInWindow)
            windowOrigin = window?.frame.origin
        } else {
            rotating = true
            lastRotationPoint = event.locationInWindow
            lastRotationTime = event.timestamp
            onRotationBegan?()
        }
    }
    override func mouseDragged(with event: NSEvent) {
        if rotating {
            let point = event.locationInWindow
            onRotationChanged?(Double(point.x-lastRotationPoint.x),Double(point.y-lastRotationPoint.y),event.timestamp-lastRotationTime)
            lastRotationPoint = point; lastRotationTime = event.timestamp
            return
        }
        guard let start = dragOrigin, let origin = windowOrigin else { return }
        guard let location = window?.convertPoint(toScreen: event.locationInWindow) else { return }
        window?.setFrameOrigin(NSPoint(x: origin.x + location.x - start.x, y: origin.y + location.y - start.y))
    }
    override func mouseUp(with event: NSEvent) {
        finishGesture()
    }
    private func finishGesture() {
        if rotating { onRotationEnded?() }
        if dragOrigin != nil { onDragEnded?() }
        rotating = false; dragOrigin = nil; windowOrigin = nil
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
        // AppKit must leave mouse drags to the rotation handler. Window placement
        // uses our explicit Option-drag path, which still calls setFrameOrigin.
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let content = DragHostingView(rootView: PetView(model: model))
        content.onDragEnded = { [weak self] in self?.clampAndSave() }
        content.onRotationBegan = { [weak model] in model?.beginRotation() }
        content.onRotationChanged = { [weak model] dx,dy,dt in model?.rotate(dx: dx,dy: dy,dt: dt) }
        content.onRotationEnded = { [weak model] in model?.endRotation() }
        content.onResetRotation = { [weak model] in model?.resetRotation() }
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
