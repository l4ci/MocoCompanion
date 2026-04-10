import SwiftUI

/// Horizontal stack of status icon badges (rule origin, link, sync status, lock).
/// Accepts optional parameters so callers with partial data can use the same component.
struct EntryStatusIcons: View {
    var syncStatus: SyncStatus? = nil
    var isLocked: Bool
    var isBilled: Bool = false
    var isLinkedToAppBlock: Bool = false
    var isFromRule: Bool = false
    var iconSize: CGFloat = Theme.FontSize.subhead

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            if isFromRule {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: iconSize))
                    .foregroundStyle(Color.accentColor.opacity(0.85))
                    .help("Created by an autotracker rule")
            }

            if isLinkedToAppBlock {
                Image(systemName: "link")
                    .font(.system(size: iconSize))
                    .foregroundStyle(theme.textTertiary)
                    .help("Linked to recorded activity")
            }

            if let syncStatus {
                syncIcon(syncStatus)
            }

            if isBilled {
                Image(systemName: "banknote")
                    .font(.system(size: iconSize))
                    .foregroundStyle(theme.textTertiary)
                    .help("Billed — read-only")
            }

            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func syncIcon(_ status: SyncStatus) -> some View {
        switch status {
        case .synced:
            Image(systemName: "cloud.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(theme.textTertiary.opacity(0.6))
                .help("Synced to Moco")
        case .dirty:
            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                .font(.system(size: iconSize))
                .foregroundStyle(.orange)
                .help("Pending sync")
        case .pendingCreate:
            Image(systemName: "icloud.and.arrow.up")
                .font(.system(size: iconSize))
                .foregroundStyle(.orange)
                .help("Not yet synced to Moco")
        case .pendingDelete:
            Image(systemName: "xmark.icloud")
                .font(.system(size: iconSize))
                .foregroundStyle(.red)
                .help("Pending deletion")
        }
    }
}
