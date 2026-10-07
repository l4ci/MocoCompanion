import Foundation

extension ShadowEntry {
    /// Pending drafts have no server id. Keep their local identity through promotion.
    var uiIdentity: String {
        if let localId { return "loc:\(localId)" }
        return TimelineViewModel.entryKey(for: self)
    }

    func matchesServerSelection(_ selection: Int?) -> Bool {
        guard let id, let selection else { return false }
        return id == selection
    }
}
