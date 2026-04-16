import Foundation

@MainActor
final class RestoreState {
    let restorePlanner = RestorePlanner()
    let bootPersistedWindowRestoreCatalog: PersistedWindowRestoreCatalog

    var nativeFullscreenRecordsByOriginalToken: [WindowToken: WorkspaceManager.NativeFullscreenRecord] = [:]
    var nativeFullscreenOriginalTokenByCurrentToken: [WindowToken: WindowToken] = [:]
    var consumedBootPersistedWindowRestoreKeys: Set<PersistedWindowRestoreKey> = []
    var persistedWindowRestoreCatalogDirty = false
    var persistedWindowRestoreCatalogSaveScheduled = false

    init(settings: SettingsStore) {
        bootPersistedWindowRestoreCatalog = settings.loadPersistedWindowRestoreCatalog()
    }
}
