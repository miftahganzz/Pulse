import SwiftUI

public struct SecurityPortsView: View {
    @ObservedObject var manager: ServerConnectionManager
    @State private var searchText = ""
    @State private var filterMode = 0 // 0: All, 1: Public, 2: Sensitive, 3: Localhost

    public init(manager: ServerConnectionManager) {
        self.manager = manager
    }

    private var allPorts: [ListeningPortItem] {
        manager.securitySnapshot?.ports ?? []
    }

    private var filteredPorts: [ListeningPortItem] {
        var list = allPorts

        switch filterMode {
        case 1:
            list = list.filter { $0.exposure == .public }
        case 2:
            list = list.filter { $0.isSensitive }
        case 3:
            list = list.filter { $0.exposure == .localhost }
        default:
            break
        }

        if !searchText.isEmpty {
            list = list.filter {
                String($0.port).contains(searchText) ||
                $0.processName.localizedCaseInsensitiveContains(searchText) ||
                $0.ip.contains(searchText) ||
                $0.protocolType.localizedCaseInsensitiveContains(searchText)
            }
        }

        return list.sorted {
            if $0.isSensitive != $1.isSensitive {
                return $0.isSensitive && !$1.isSensitive
            }
            if $0.exposure != $1.exposure {
                return $0.exposure == .public
            }
            return $0.port < $1.port
        }
    }

    public var body: some View {
        VStack(spacing: 16) {
            // 1. KPI Summary Cards
            let snap = manager.securitySnapshot
            let totalPorts = snap?.ports.count ?? 0
            let publicPorts = snap?.publicCount ?? 0
            let sensitivePorts = snap?.sensitiveCount ?? 0
            let fw = snap?.firewall

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                SecurityKPICard(
                    title: "Total Sockets",
                    value: "\(totalPorts)",
                    icon: "network",
                    tint: .blue,
                    caption: "Active listening"
                )

                SecurityKPICard(
                    title: "Publicly Bound",
                    value: "\(publicPorts)",
                    icon: "globe",
                    tint: publicPorts > 0 ? .orange : .secondary,
                    caption: "Listening on 0.0.0.0 / ::"
                )

                SecurityKPICard(
                    title: "Sensitive Alerts",
                    value: "\(sensitivePorts)",
                    icon: sensitivePorts > 0 ? "exclamationmark.shield.fill" : "checkmark.shield.fill",
                    tint: sensitivePorts > 0 ? .red : .green,
                    caption: sensitivePorts > 0 ? "High risk exposed ports" : "No sensitive ports open"
                )

                SecurityKPICard(
                    title: "Host Firewall",
                    value: fw?.isActive == true ? "Active" : "Inactive",
                    icon: fw?.isActive == true ? "lock.shield.fill" : "lock.slash",
                    tint: fw?.isActive == true ? .green : .orange,
                    caption: fw != nil ? "\(fw!.type.uppercased()) · In: \(fw!.defaultIncoming)" : "Status pending"
                )
            }

            // 2. Sensitive Warning Banner
            if sensitivePorts > 0 {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(sensitivePorts) Critical Port\(sensitivePorts > 1 ? "s" : "") Exposed to the Public Internet")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.red)

                        Text("Database or internal service ports are bound to 0.0.0.0 without private network containment. Inspect table below for remediation.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Filter Sensitive") {
                        filterMode = 2
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.red.opacity(0.25), lineWidth: 1)
                )
            }

            // 3. Search & Filter Bar
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("Search port, process, or IP...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                Picker("", selection: $filterMode) {
                    Text("All (\(allPorts.count))").tag(0)
                    Text("Public (\(publicPorts))").tag(1)
                    Text("Sensitive (\(sensitivePorts))").tag(2)
                    Text("Localhost").tag(3)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()

                Button(action: { manager.refreshSecurity() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(manager.isLoadingSecurity)
            }

            // 4. Ports Table
            if manager.isLoadingSecurity && allPorts.isEmpty {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning listening network sockets...").foregroundColor(.secondary).font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: 200)
            } else if filteredPorts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "slash.circle")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No listening ports match the selected filter.")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: 200)
            } else {
                Table(filteredPorts) {
                    TableColumn("Port / Proto") { item in
                        HStack(spacing: 6) {
                            Text(verbatim: "\(item.port)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                            Text(item.protocolType.uppercased())
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(3)
                        }
                    }
                    .width(min: 85, ideal: 95, max: 110)

                    TableColumn("Process") { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.processName)
                                .font(.system(size: 12, weight: .medium))
                            if item.pid > 0 {
                                Text(verbatim: "PID: \(item.pid)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .width(min: 110, ideal: 140)

                    TableColumn("Binding Address") { item in
                        Text(item.ip)
                            .font(.system(size: 11, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    .width(min: 95, ideal: 115, max: 130)

                    TableColumn("Exposure") { item in
                        HStack(spacing: 4) {
                            Image(systemName: item.exposure.iconName)
                                .font(.system(size: 9, weight: .bold))
                            Text(item.exposure.displayTitle)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(item.exposure.badgeColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(item.exposure.badgeColor.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .width(min: 95, ideal: 110, max: 125)

                    TableColumn("Recommendation") { item in
                        if item.isSensitive {
                            HStack(spacing: 5) {
                                Image(systemName: "exclamationmark.shield.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 11))
                                Text(item.recommendation ?? "Sensitive database port exposed to public internet!")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.red)
                                    .lineLimit(1)
                            }
                        } else if item.exposure == .public {
                            Text("Standard public service")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        } else {
                            Text("Isolated to private network / localhost")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .onAppear {
            if manager.securitySnapshot == nil {
                manager.refreshSecurity()
            }
        }
    }
}

private struct SecurityKPICard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 20, height: 20)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.primary)

            Text(caption)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
