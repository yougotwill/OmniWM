import XCTest
@testable import OmniWM

@MainActor
final class HotkeyBindingsCompatibilityTests: XCTestCase {
    func testStoredBindingsMergeWithDefaultsAndPruneUnknownIds() throws {
        let suiteName = "HotkeyBindingsCompatibilityTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Unable to create isolated UserDefaults suite")
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        var defaultsList = DefaultHotkeyBindings.all()
        guard let first = defaultsList.first else {
            return XCTFail("Expected non-empty default hotkey list")
        }

        let overridden = HotkeyBinding(
            id: first.id,
            command: first.command,
            binding: KeyBinding(keyCode: 40, modifiers: 0)
        )
        let unknown = HotkeyBinding(
            id: "unknown.binding",
            command: .toggleOverview,
            binding: KeyBinding(keyCode: 41, modifiers: 0)
        )
        let stored = [overridden, unknown]

        let encoded = try JSONEncoder().encode(stored)
        defaults.set(encoded, forKey: "settings.hotkeyBindings")

        let settings = SettingsStore(defaults: defaults)
        let merged = settings.hotkeyBindings

        XCTAssertTrue(merged.contains(where: { $0.id == first.id && $0.binding == overridden.binding }))
        XCTAssertFalse(merged.contains(where: { $0.id == unknown.id }))

        defaultsList.removeAll(where: { $0.id == first.id })
        if let expectedMissingDefault = defaultsList.first {
            XCTAssertTrue(merged.contains(where: { $0.id == expectedMissingDefault.id }))
        }

        let persistedData = try XCTUnwrap(defaults.data(forKey: "settings.hotkeyBindings"))
        let persisted = try JSONDecoder().decode([HotkeyBinding].self, from: persistedData)
        XCTAssertFalse(persisted.contains(where: { $0.id == unknown.id }))
    }
}
