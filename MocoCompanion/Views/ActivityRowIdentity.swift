import Foundation

extension ShadowEntry {
    /// Drafts keep their localId through promotion (and server refreshes), so the row
    /// identity, and with it list selection, does not change when the server id arrives.
    var uiIdentity: String {
        if let localId { return "loc:\(localId)" }
        return TimelineViewModel.entryKey(for: self)
    }

    func matchesServerSelection(_ selection: Int?) -> Bool {
        guard let id, let selection else { return false }
        return id == selection
    }
}
