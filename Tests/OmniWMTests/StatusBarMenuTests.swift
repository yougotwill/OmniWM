import AppKit
import Testing

@testable import OmniWM

@Suite(.serialized) @MainActor struct StatusBarMenuTests {
    @Test func buildMenuUsesCurrentAppAppearanceForMenuAndViews() throws {
        let application = NSApplication.shared
        let originalAppearance = application.appearance
        defer { application.appearance = originalAppearance }

        let controller = makeLayoutPlanTestController()
        let builder = StatusBarMenuBuilder(settings: controller.settings, controller: controller)

        application.appearance = NSAppearance(named: .aqua)
        let lightMenu = builder.buildMenu()

        #expect(lightMenu.appearance?.name == .aqua)
        #expect(try #require(lightMenu.items.first?.view).appearance?.name == .aqua)
        #expect(try #require(lightMenu.items.dropFirst(3).first?.view).appearance?.name == .aqua)

        application.appearance = NSAppearance(named: .darkAqua)
        let darkMenu = builder.buildMenu()

        #expect(darkMenu.appearance?.name == .darkAqua)
        #expect(try #require(darkMenu.items.first?.view).appearance?.name == .darkAqua)
        #expect(try #require(darkMenu.items.dropFirst(3).first?.view).appearance?.name == .darkAqua)
    }

    @Test func buildMenuIncludesSettingsFileActions() {
        let controller = makeLayoutPlanTestController()
        let builder = StatusBarMenuBuilder(settings: controller.settings, controller: controller)

        let menu = builder.buildMenu()
        let labels = menu.items.compactMap(\.view).flatMap(textLabels(in:))

        #expect(labels.contains("Export Editable Config"))
        #expect(labels.contains("Export Compact Backup"))
        #expect(labels.contains("Reveal Settings File"))
        #expect(labels.contains("Open Settings File"))
    }

    @Test func exportActionReportsSuccessAlert() {
        let controller = makeLayoutPlanTestController()
        let builder = StatusBarMenuBuilder(settings: controller.settings, controller: controller)
        var received: [(String, String)] = []
        builder.infoAlertPresenter = { title, message in
            received.append((title, message))
        }

        builder.performSettingsMenuAction(.export(.full))

        #expect(received.count == 1)
        #expect(received.first?.0 == "Editable Config Exported")
        #expect(received.first?.1 == SettingsStore.exportURL.path)
    }

    @Test func revealActionCreatesFileAndReportsSuccessAlert() {
        let controller = makeLayoutPlanTestController()
        let settings = controller.settings
        let builder = StatusBarMenuBuilder(settings: settings, controller: controller)
        var received: [(String, String)] = []
        builder.infoAlertPresenter = { title, message in
            received.append((title, message))
        }
        let exportURL = SettingsStore.exportURL
        defer { try? FileManager.default.removeItem(at: exportURL) }
        try? FileManager.default.removeItem(at: exportURL)

        builder.performSettingsMenuAction(.revealSettingsFile)

        #expect(settings.settingsFileExists == true)
        #expect(received.count == 1)
        #expect(received.first?.0 == "Settings File Created")
        #expect(received.first?.1 == SettingsStore.exportURL.path)
    }

    private func textLabels(in view: NSView) -> [String] {
        let direct = (view as? NSTextField).map(\.stringValue).map { [$0] } ?? []
        return direct + view.subviews.flatMap(textLabels(in:))
    }
}
