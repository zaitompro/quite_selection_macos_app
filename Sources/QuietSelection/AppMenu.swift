import AppKit

@MainActor
@objc protocol AppMenuActions {
    func showSettings()
    func closeSettings()
    func quitApplication()
}

@MainActor
enum AppMenu {
    private static func settingsItem(target: any AppMenuActions, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: "Настройки…", action: #selector(AppMenuActions.showSettings), keyEquivalent: key)
        item.target = target
        return item
    }
    private static func quitItem(target: any AppMenuActions) -> NSMenuItem {
        // Deliberately has no shortcut: quitting must be an explicit choice.
        let item = NSMenuItem(title: "Завершить QuietSelection", action: #selector(AppMenuActions.quitApplication), keyEquivalent: "")
        item.target = target
        return item
    }
    static func status(target: any AppMenuActions, version: String) -> NSMenu {
        let menu = NSMenu()
        menu.font = .systemFont(ofSize: 17)
        let versionItem = NSMenuItem(title: "QuietSelection \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())
        menu.addItem(settingsItem(target: target))
        menu.addItem(quitItem(target: target))
        return menu
    }
    static func make(target: any AppMenuActions) -> NSMenu {
        let menu = NSMenu()
        let application = NSMenuItem()
        let applicationMenu = NSMenu(title: "QuietSelection")
        applicationMenu.addItem(settingsItem(target: target, key: ","))
        let close = NSMenuItem(title: "Закрыть настройки", action: #selector(AppMenuActions.closeSettings), keyEquivalent: "q")
        close.target = target
        applicationMenu.addItem(close)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(quitItem(target: target))
        application.submenu = applicationMenu
        menu.addItem(application)

        let window = NSMenuItem()
        let windowMenu = NSMenu(title: "Окно")
        let closeWindow = NSMenuItem(title: "Закрыть настройки", action: #selector(AppMenuActions.closeSettings), keyEquivalent: "w")
        closeWindow.target = target
        windowMenu.addItem(closeWindow)
        window.submenu = windowMenu
        menu.addItem(window)
        return menu
    }
}
