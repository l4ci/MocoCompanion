import SwiftUI

/// Favorites settings tab: enable/disable, reorder, and remove favorites.
struct FavoritesSettingsTab: View {
    @Bindable var settings: SettingsStore
    var favoritesManager: FavoritesManager?

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "settings.showFavorites"), isOn: $settings.favoritesEnabled)
            } header: {
                Text(String(localized: "settings.display"))
            }

            if settings.favoritesEnabled, let favoritesManager {
                if favoritesManager.favorites.isEmpty {
                    Section {
                        Text(String(localized: "settings.favoritesEmpty"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } header: {
                        Text(String(localized: "settings.favoritesHeader"))
                    }
                } else {
                    Section {
                        List {
                            ForEach(favoritesManager.favorites) { fav in
                                HStack {
                                    Image(systemName: "line.3.horizontal")
                                        .foregroundStyle(.tertiary)
                                        .font(.system(size: 12))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(fav.projectName)
                                            .font(.system(size: 12, weight: .medium))
                                            .lineLimit(1)
                                        Text(fav.taskName)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .padding(.vertical, 2)

                                    Spacer()
                                    Button {
                                        favoritesManager.remove(id: fav.id)
                                    } label: {
                                        Image(systemName: "xmark.circle")
                                            .foregroundStyle(.secondary)
                                            .font(.system(size: 12))
                                    }
                                    .buttonStyle(.plain)
                                    .help(String(localized: "settings.removeFavorite"))
                                }
                            }
                            .onMove { source, destination in
                                favoritesManager.move(fromOffsets: source, toOffset: destination)
                            }
                        }
                        .frame(height: min(CGFloat(favoritesManager.favorites.count) * 44, 300))
                    } header: {
                        Text(String(localized: "settings.favoritesHeader"))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
