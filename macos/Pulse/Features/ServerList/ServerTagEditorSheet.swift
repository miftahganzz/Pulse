import SwiftUI

/// Sheet to edit a server's environment and custom tags
struct ServerTagEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ServerStore.shared

    let server: ServerModel

    @State private var selectedEnvironment: ServerEnvironment
    @State private var tagsText: String   // comma-separated raw input
    @State private var newTag: String = ""

    init(server: ServerModel) {
        self.server = server
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
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text("Edit Tags — \(server.name)")
                        .font(.system(size: 14, weight: .bold))
                }
                Spacer()
                Button("Done") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Environment picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Environment")
                            .font(.headline)
                        Text("Groups this server in the sidebar.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 10) {
                            ForEach(ServerEnvironment.allCases) { env in
                                envButton(env)
                            }
                        }
                    }

                    Divider()

                    // Custom tags
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom Tags")
                            .font(.headline)
                        Text("Free-form labels for quick filtering.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Current tag chips
                        if !parsedTags.isEmpty {
                            FlowTagLayout(tags: parsedTags) { tag in
                                withAnimation {
                                    var updated = parsedTags
                                    updated.removeAll { $0 == tag }
                                    tagsText = updated.joined(separator: ", ")
                                }
                            }
                        }

                        // Add tag input
                        HStack {
                            TextField("Add tag (e.g. nginx, geo-sg, k8s)", text: $newTag)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { addTag() }
                            Button("Add") { addTag() }
                                .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 420, height: 360)
    }

    // MARK: - Helpers

    private func envButton(_ env: ServerEnvironment) -> some View {
        let isSelected = selectedEnvironment == env
        return Button {
            selectedEnvironment = env
        } label: {
            HStack(spacing: 6) {
                Image(systemName: env.icon)
                    .font(.system(size: 11))
                Text(env.rawValue)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? env.color.opacity(0.15) : Color(NSColor.controlBackgroundColor))
            .foregroundColor(isSelected ? env.color : .primary)
            .cornerRadius(7)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isSelected ? env.color : Color(NSColor.separatorColor), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !parsedTags.contains(tag) else { return }
        let updated = parsedTags + [tag]
        tagsText = updated.joined(separator: ", ")
        newTag = ""
    }

    private func save() {
        store.updateServer(server, environment: selectedEnvironment, tags: parsedTags)
    }
}

// MARK: - Flow tag layout (wraps chips)

private struct FlowTagLayout: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        // Simple horizontal wrapping using LazyVGrid
        let columns = [GridItem(.adaptive(minimum: 60, maximum: 160), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag)
                        .font(.system(size: 11, weight: .medium))
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
                .cornerRadius(6)
            }
        }
    }
}
