import Foundation
enum SettingsMigration {
    struct Patches: OptionSet {
        let rawValue: Int

        static let rewriteForZigNativeDefaults = Patches(rawValue: 1 << 1)
    }

    private static let patchesKey = "appliedSettingsPatches"
    private static let defaultLayoutTypeKey = "settings.defaultLayoutType"
    private static let workspaceConfigurationsKey = "settings.workspaceConfigurations"
    private static let workspaceSettingsMigratedKey = "settings.workspaceSettingsMigrated"
    private static let persistentWorkspacesKey = "settings.persistentWorkspaces"
    private static let workspaceAssignmentsKey = "settings.workspaceAssignments"
    private static let hotkeyBindingsKey = "settings.hotkeyBindings"

    static func run(defaults: UserDefaults = .standard) {
        var applied = Patches(rawValue: defaults.integer(forKey: patchesKey))

        if !applied.contains(.rewriteForZigNativeDefaults),
           rewriteForZigNativeDefaults(defaults: defaults)
        {
            applied.insert(.rewriteForZigNativeDefaults)
        }

        defaults.set(applied.rawValue, forKey: patchesKey)
    }

    @discardableResult
    private static func rewriteForZigNativeDefaults(defaults: UserDefaults) -> Bool {
        guard let hotkeyData = try? JSONEncoder().encode(DefaultHotkeyBindings.all()) else {
            return false
        }

        if let rewrittenWorkspaceConfigurations = rewrittenWorkspaceConfigurations(defaults: defaults) {
            guard let workspaceData = try? JSONEncoder().encode(rewrittenWorkspaceConfigurations) else {
                return false
            }
            defaults.set(workspaceData, forKey: workspaceConfigurationsKey)
            defaults.set(true, forKey: workspaceSettingsMigratedKey)
        }

        defaults.set(LayoutType.niri.rawValue, forKey: defaultLayoutTypeKey)
        defaults.set(hotkeyData, forKey: hotkeyBindingsKey)
        return true
    }

    private static func rewrittenWorkspaceConfigurations(defaults: UserDefaults) -> [WorkspaceConfiguration]? {
        if let data = defaults.data(forKey: workspaceConfigurationsKey),
           let configurations = try? JSONDecoder().decode([WorkspaceConfiguration].self, from: data)
        {
            return configurations.map { config in
                WorkspaceConfiguration(
                    id: config.id,
                    name: config.name,
                    displayName: config.displayName,
                    monitorAssignment: config.monitorAssignment,
                    layoutType: .defaultLayout,
                    isPersistent: config.isPersistent
                )
            }
        }

        let legacyConfigurations = legacyWorkspaceConfigurations(defaults: defaults)
        return legacyConfigurations.isEmpty ? nil : legacyConfigurations
    }

    private static func legacyWorkspaceConfigurations(defaults: UserDefaults) -> [WorkspaceConfiguration] {
        var result: [WorkspaceConfiguration] = []
        var seen: Set<String> = []

        let persistentNames = defaults.string(forKey: persistentWorkspacesKey)?
            .split { $0 == "," || $0 == "\n" || $0 == "\r" }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        var assignments: [String: MonitorAssignment] = [:]
        for line in (defaults.string(forKey: workspaceAssignmentsKey) ?? "").split(whereSeparator: \.isNewline) {
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.contains(":")
                ? trimmed.split(separator: ":", maxSplits: 1)
                : trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let name = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let monitorString = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let firstMonitor = monitorString.split(separator: ",").first
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? monitorString
            assignments[name] = MonitorAssignment.fromString(firstMonitor)
        }

        for name in persistentNames {
            guard !seen.contains(name) else { continue }
            guard case .success = WorkspaceName.parse(name) else { continue }
            seen.insert(name)
            result.append(WorkspaceConfiguration(
                name: name,
                monitorAssignment: assignments[name] ?? .any,
                layoutType: .defaultLayout,
                isPersistent: true
            ))
        }

        for (name, assignment) in assignments where !seen.contains(name) {
            guard case .success = WorkspaceName.parse(name) else { continue }
            seen.insert(name)
            result.append(WorkspaceConfiguration(
                name: name,
                monitorAssignment: assignment,
                layoutType: .defaultLayout,
                isPersistent: false
            ))
        }

        return result
    }
}
