import FeatherAppModel
import FeatherCore

// The Mac's Share hand-off reaches the shared model here (app target only: InboxHandOff.swift is also compiled
// into the Share extension, which doesn't link FeatherAppModel).
extension AppModel {
    /// Collects Share capture `id` (from `feathermark://inbox?id=…`) into the inbox, then files it; returns the
    /// number of notes created.
    @discardableResult
    func collectHandOff(id: ULID, prefix: String = InboxHandOff.defaultPrefix) async -> Int {
        await attempt { try InboxHandOff.collect(id: id, into: inbox, prefix: prefix) }
        return await drainInbox()
    }
}
