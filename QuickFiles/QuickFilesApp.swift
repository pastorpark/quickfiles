import SwiftUI
import AppKit
import Combine

@main
struct QuickFilesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(store: appDelegate.store)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SettingsStore()
    private lazy var panelController = PanelController(store: store)
    private lazy var settingsWindowController = SettingsWindowController(store: store)
    private let hotKeyController = HotKeyController()
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        hotKeyController.onPressed = { [weak self] in
            self?.panelController.toggle()
        }
        hotKeyController.register(store.hotKey)
        panelController.startMonitoring()

        store.$hotKey
            .dropFirst()
            .sink { [weak self] hotKey in
                self?.hotKeyController.register(hotKey)
            }
            .store(in: &cancellables)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: "QuickFiles")

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "QuickFiles 열기", action: #selector(openPanel), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(title: "설정", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "종료", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    @objc private func openPanel() {
        panelController.show()
    }

    @objc private func openSettings() {
        settingsWindowController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
