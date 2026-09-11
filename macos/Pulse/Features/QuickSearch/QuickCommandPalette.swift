import SwiftUI

public struct QuickCommandPalette: View {
    @ObservedObject private var pool = ServerConnectionPool.shared
    @ObservedObject private var store = ServerStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    var onSelectServer: (ServerModel) -> Void
    var onSelectAllServers: () -> Void
    var onOpenSettings: () -> Void

    public init(
        onSelectServer: @escaping (ServerModel) -> Void,
        onSelectAllServers: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.onSelectServer = onSelectServer
        self.onSelectAllServers = onSelectAllServers
        self.onOpenSettings = onOpenSettings
    }

    struct SearchResultItem: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let category: String
        let action: () -> Void
    }

    private var results: [SearchResultItem] {
        var items: [SearchResultItem] = []

        // Global Navigation Actions
        items.append(SearchResultItem(
            title: "All Servers Overview",
            subtitle: "\(store.servers.count) servers configured",
            icon: "square.grid.2x2",
            category: "Navigation",
            action: {
                onSelectAllServers()
                dismiss()
            }
        ))

        items.append(SearchResultItem(
            title: "Settings",
            subtitle: "General, notifications, appearance & intervals",
            icon: "gearshape",
            category: "Navigation",
            action: {
                onOpenSettings()
                dismiss()
            }
        ))

        // Servers
        for server in store.servers {
            let mgr = pool.manager(for: server)
            items.append(SearchResultItem(
                title: server.name,
                subtitle: "\(server.address):\(server.port) · \(mgr.state.displayStatus)",
                icon: "server.rack",
                category: "Servers",
                action: {
                    onSelectServer(server)
                    dismiss()
                }
            ))

            // Monitors inside this server
            for monitor in mgr.monitors {
                items.append(SearchResultItem(
                    title: monitor.name,
                    subtitle: "\(server.name) · \(monitor.type.displayName) (\(monitor.status.displayName))",
                    icon: monitor.type.sfSymbol,
                    category: "Monitors",
                    action: {
                        onSelectServer(server)
                        dismiss()
                    }
                ))
            }

            // Incidents inside this server
            for incident in mgr.incidents where incident.status != .resolved {
                items.append(SearchResultItem(
                    title: "\(incident.title) (Incident)",
                    subtitle: "\(server.name) · Downtime \(incident.formattedDuration)",
                    icon: "exclamationmark.triangle.fill",
                    category: "Incidents",
                    action: {
                        onSelectServer(server)
                        dismiss()
                    }
                ))
            }
        }

        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return items
        }

        let q = query.lowercased()
        return items.filter {
            $0.title.lowercased().contains(q) ||
            $0.subtitle.lowercased().contains(q) ||
            $0.category.lowercased().contains(q)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search Input Header
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))

                TextField("Search servers, services, incidents or commands...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))

                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button("ESC") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(4)
            }
            .padding(14)

            Divider()

            // Search Results List
            if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No results for \"\(query)\"")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                List {
                    let grouped = Dictionary(grouping: results, by: { $0.category })
                    ForEach(grouped.keys.sorted(), id: \.self) { category in
                        Section(category) {
                            ForEach(grouped[category] ?? []) { item in
                                Button(action: item.action) {
                                    HStack(spacing: 12) {
                                        Image(systemName: item.icon)
                                            .font(.system(size: 14))
                                            .frame(width: 20)
                                            .foregroundColor(.accentColor)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.primary)
                                            Text(item.subtitle)
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "arrow.return")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary.opacity(0.6))
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .frame(width: 520, height: 380)
    }
}
