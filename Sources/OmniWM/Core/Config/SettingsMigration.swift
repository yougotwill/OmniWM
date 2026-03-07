import Foundation
enum SettingsMigration {
    struct Patches: OptionSet {
        let rawValue: Int
    }
    private static let patchesKey = "appliedSettingsPatches"
    static func run(defaults: UserDefaults = .standard) {
        let applied = Patches(rawValue: defaults.integer(forKey: patchesKey))
        _ = applied
    }
}
