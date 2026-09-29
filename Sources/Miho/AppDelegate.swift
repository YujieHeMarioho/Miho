import AppKit
import SwiftUI

@available(macOS 14.2, *)
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: CompanionModel!
    private var companion: DesktopCompanion!
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var visibilityItem: NSMenuItem!
    private var isVisible = true
    private var infoWindow: NSWindow?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model = CompanionModel()
        companion = DesktopCompanion(model: model)
        buildMenu()
        companion.contextMenu = statusItem.menu
        if CommandLine.arguments.contains("--diagnostics") { showInfo() }
        if CommandLine.arguments.contains("--probe") {
            model.setEnabled(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self else { return }
                print("callbacks=\(self.model.callbackCount) audible=\(self.model.audibleCallbackCount) beats=\(self.model.beats) energy=\(self.model.motion.energy)")
                NSApp.terminate(nil)
            }
        } else if !UserDefaults.standard.bool(forKey: "hasSeenWelcome") {
            showWelcome()
        } else if UserDefaults.standard.bool(forKey: "captureEnabled") {
            model.setEnabled(true)
        }
    }

    private func showWelcome() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "你好，我是 Miho 迷糊 🌱"
        alert.informativeText = "放首歌，我就会跟着跳舞。\n\nMiho 会申请捕获电脑播放的声音，只在本机实时分析，不保存、不上传，也不使用麦克风。你可以随时从菜单栏暂停。\n\n拖动小团子可以换位置。"
        alert.addButton(withTitle: "开始听音乐")
        alert.addButton(withTitle: "先陪我待着")
        let response = alert.runModal()
        UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
        model.setEnabled(response == .alertFirstButtonReturn)
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "Miho 迷糊")
            button.toolTip = "Miho · 桌面音乐精灵"
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        let title = NSMenuItem(title: "Miho 迷糊 🌱", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        statusMenuItem = NSMenuItem(title: model.status, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        pauseItem = item("暂停律动", #selector(togglePause))
        menu.addItem(pauseItem)
        visibilityItem = item("隐藏 Miho", #selector(toggleVisible))
        menu.addItem(visibilityItem)
        menu.addItem(.separator())
        let sliderItem = NSMenuItem()
        sliderItem.view = NSHostingView(rootView: SensitivityView(model: model))
        sliderItem.view?.frame = NSRect(x: 0, y: 0, width: 230, height: 67)
        menu.addItem(sliderItem)
        menu.addItem(.separator())
        menu.addItem(item("重试音频连接", #selector(retry)))
        menu.addItem(item("打开音频捕获权限设置…", #selector(openPermissions)))
        menu.addItem(item("关于 Miho 与连接状态…", #selector(showInfo)))
        menu.addItem(.separator())
        menu.addItem(item("退出 Miho", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    public func menuWillOpen(_ menu: NSMenu) {
        statusMenuItem.title = model.status
        pauseItem.title = model.enabled ? "暂停律动" : "开始律动"
        visibilityItem.title = isVisible ? "隐藏 Miho" : "显示 Miho"
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        isVisible = true
        companion?.setVisible(true)
        return true
    }

    @objc private func togglePause() { model.setEnabled(!model.enabled) }
    @objc private func toggleVisible() { isVisible.toggle(); companion.setVisible(isVisible) }
    @objc private func retry() { model.retry() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func showInfo() {
        if infoWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 340),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "关于 Miho"
            window.contentView = NSHostingView(rootView: InfoView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            infoWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        infoWindow?.makeKeyAndOrderFront(nil)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
        companion?.dispose()
    }
}

@available(macOS 14.2, *)
private struct SensitivityView: View {
    @ObservedObject var model: CompanionModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("律动灵敏度").font(.system(size: 12))
                Spacer()
                Text(String(format: "%.1f×", model.sensitivity)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Slider(value: $model.sensitivity, in: 0.5...2, step: 0.1)
                .accessibilityLabel("律动灵敏度")
        }.padding(.horizontal, 16).padding(.vertical, 8)
    }
}

@available(macOS 14.2, *)
private struct InfoView: View {
    @ObservedObject var model: CompanionModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Miho 迷糊 🌱").font(.system(size: 27, weight: .semibold, design: .rounded))
            Text("Tencent Music Hackathon · 腾讯音乐黑客松").font(.system(size: 12)).foregroundStyle(.secondary)
            Text("一个陪你听音乐、跟着声音跳舞的小团子。\n拖动它换位置，从菜单栏调整律动。")
                .font(.system(size: 13))
            Divider()
            Text(model.status).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Text("音频回调：\(model.callbackCount)  ·  有声音：\(model.audibleCallbackCount)\n检测到的鼓点：\(model.beats)")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            Text("声音只在本机内存中实时处理，不保存、不上传。\n如果正在播放却没反应，请检查音频捕获权限并重试。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }.padding(24).frame(width: 390, height: 340)
    }
}
