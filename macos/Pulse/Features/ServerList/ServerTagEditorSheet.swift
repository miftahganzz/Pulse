import SwiftUI

/// Modern sheet to edit server details: name, host/port, environment group, and custom tags.
struct ServerTagEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ServerStore.shared

    let server: ServerModel

    @State private var serverName: String
    @State private var address: String
    @State private var portString: String
    @State private var selectedEnvironment: ServerEnvironment
    @State private var tagsText: String
    @State private var newTag: String = ""
    @State private var errorMessage: String? = nil

    init(server: ServerModel) {
        self.server = server
        _serverName = State(initialValue: server.name)
        _address = State(initialValue: server.address)
        _portString = State(initialValue: "\(server.port)")
        _selectedEnvironment = State(initialValue: server.environment)
        _tagsText = State(initialValue: server.tags.joined(separator: ", "))
    }

    private var parsedTags: [String] {
        tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Modal Header
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Edit Server")
                        .font(.system(size: 14, weight: .bold))
                    Text(server.name)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let err = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(err)
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }

                    // 1. General Info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("General Information")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Server Display Name")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            TextField("e.g. Production Web or Mifz2", text: $serverName)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Address / Host")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("e.g. 100.103.40.120 or api.pulse.net", text: $address)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Port")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("8443", text: $portString)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                            }
                        }
                    }

                    Divider()

                    // 2. Environment Group
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Environment Group")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)

                        Text("Categorizes and groups this server in the sidebar.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 8) {
                            ForEach(ServerEnvironment.allCases) { env in
                                envGridCard(env)
                            }
                        }
                    }

                    Divider()

                    // 3. Custom Tags
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom Tags")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)

                        Text("Free-form tags for quick search, filtering, and organization.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if !parsedTags.isEmpty {
                            FlowTagLayout(tags: parsedTags) { tag in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    var updated = parsedTags
                                    updated.removeAll { $0 == tag }
                                    tagsText = updated.joined(separator: ", ")
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            TextField("Add tag (e.g. nginx, geo-sg, k8s)", text: $newTag)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { addTag() }

                            Button("Add") {
                                addTag()
                            }
                            .buttonStyle(.bordered)
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 480, height: 490)
    }

    // MARK: - Subviews

    private func envGridCard(_ env: ServerEnvironment) -> some View {
        let isSelected = selectedEnvironment == env
        return Button {
            selectedEnvironment = env
        } label: {
            HStack(spacing: 8) {
                Image(systemName: env.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(env.color)
                    .frame(width: 18)

                Text(env.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize()

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(env.color)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? env.color.opacity(0.12) : Color(NSColor.controlBackgroundColor))
            .foregroundColor(isSelected ? env.color : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? env.color.opacity(0.8) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !parsedTags.contains(tag) else { return }
        let updated = parsedTags + [tag]
        tagsText = updated.joined(separator: ", ")
        newTag = ""
    }

    private func save() {
        let cleanName = serverName.trimmingCharacters(in: .whitespaces)
        let cleanAddress = address.trimmingCharacters(in: .whitespaces)
        guard !cleanName.isEmpty else {
            errorMessage = "Server display name cannot be empty."
            return
        }
        guard !cleanAddress.isEmpty else {
            errorMessage = "Server address cannot be empty."
            return
        }
        guard let port = Int(portString), port > 0, port <= 65535 else {
            errorMessage = "Port must be a valid number between 1 and 65535."
            return
        }

        errorMessage = nil
        store.updateServer(
            server,
            name: cleanName,
            address: cleanAddress,
            port: port,
            environment: selectedEnvironment,
            tags: parsedTags
        )
        ServerConnectionPool.shared.manager(for: server).updateConfig(
            name: cleanName,
            address: cleanAddress,
            port: port
        )
        dismiss()
    }
}

// MARK: - Flow Tag Layout

private struct FlowTagLayout: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 70, maximum: 180), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 5) {
                    Text(tag)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Button {
                        onRemove(tag)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12))
                .foregroundColor(.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }
}
