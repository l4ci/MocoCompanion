import AppKit
import SwiftUI

/// Renders a single app usage block on the timeline.
/// Positioned by the parent via offset; height derived from duration.
struct AppUsageBlockView: View {
    let block: AppUsageBlock
    let isSelected: Bool
    var rulesEnabled: Bool = true
    var onSelect: (_ shiftHeld: Bool) -> Void = { _ in }
    var onCreateRule: ((_ bundleId: String, _ appName: String) -> Void)?
    var onCreateEntry: ((AppUsageBlock) -> Void)?
    var onDragStarted: () -> Void = {}
    var onDragUpdated: (_ targetY: CGFloat) -> Void = { _ in }
    var onDragEnded: () -> Void = {}
    @Environment(\.theme) private var theme
    @State private var isDragging: Bool = false
    @State private var appIcon: NSImage?

    private var height: CGFloat {
        max(CGFloat(block.durationSeconds / 60) * TimelineLayout.pixelsPerMinute, 12)
    }

    /// Resolves the app's icon from its bundle ID via NSWorkspace. Cached in
    /// `@State` for the lifetime of the view so we don't hit the filesystem
    /// on every render.
    private func resolveAppIcon() {
        guard appIcon == nil else { return }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: block.appBundleId)
        if let url {
            appIcon = NSWorkspace.shared.icon(forFile: url.path)
        }
    }

    private var helpLabel: String {
        var lines = ["\(block.appName) — \(block.durationLabel) (\(block.startTimeLabel) – \(block.endTimeLabel))"]
        if !block.contributingApps.isEmpty {
            lines.append("")
            lines.append("Also in this window:")
            for contrib in block.contributingApps {
                lines.append("• \(contrib.appName): \(contrib.durationLabel)")
            }
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left color accent bar
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor.opacity(0.6))
                .frame(width: 3)

            // App icon (resolved from bundle id via NSWorkspace)
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .padding(.leading, 5)
            }

            Text(block.appName)
                .font(.system(size: Theme.FontSize.subhead))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 5)

            Spacer(minLength: 0)
        }
        .onAppear { resolveAppIcon() }
        .onChange(of: block.appBundleId) { _, _ in resolveAppIcon() }
        .frame(width: TimelineLayout.appUsagePaneWidth - 8, height: height)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .stroke(Color.accentColor, lineWidth: 2)
                .opacity(isSelected ? 1 : 0)
        }
        .help(helpLabel)
        .opacity(isDragging ? 0.5 : 1.0)
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        onDragStarted()
                    }
                    onDragUpdated(value.location.y)
                }
                .onEnded { _ in
                    isDragging = false
                    onDragEnded()
                }
        )
        .onTapGesture(count: 1) {
            onSelect(NSEvent.modifierFlags.contains(.shift))
        }
        .onTapGesture(count: 2) {
            onCreateEntry?(block)
        }
        .contextMenu {
            Button("Create entry from this block…") {
                onCreateEntry?(block)
            }
            if rulesEnabled {
                Button("Create rule for \"\(block.appName)\"…") {
                    onCreateRule?(block.appBundleId, block.appName)
                }
            }
        }
    }
}
