import SwiftUI

struct AISettingsView: View {
    @ObservedObject var aiStore: AIProviderStore
    @State private var selectedProviderID: AIProviderConfig.ID?
    @State private var draft = EditableAIProvider()

    private var selectedProvider: AIProviderConfig? {
        guard let selectedProviderID else {
            return aiStore.providers.first
        }
        return aiStore.providers.first { $0.id == selectedProviderID } ?? aiStore.providers.first
    }

    var body: some View {
        VStack(spacing: 34) {
            VStack(spacing: 10) {
                Text("AI")
                    .font(.system(size: 42, weight: .semibold))

                Text(activeProviderText)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 42) {
                providerList
                    .frame(width: 300)

                editor
                    .frame(maxWidth: 560)
            }

            if let saveError = aiStore.saveError {
                Text(saveError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear {
            syncSelection()
        }
        .onChange(of: selectedProviderID) {
            loadDraft()
        }
        .onChange(of: aiStore.providers) {
            syncSelection()
        }
    }

    private var activeProviderText: String {
        if let provider = aiStore.activeProvider {
            return provider.name
        }
        return "未选择"
    }

    private var providerList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("接口")
                    .font(.system(size: 22, weight: .semibold))

                Spacer()

                Button {
                    let provider = aiStore.addProvider()
                    selectedProviderID = provider.id
                } label: {
                    Image(systemName: "plus")
                }
                .help("添加 AI 接口")
            }

            if aiStore.providers.isEmpty {
                Text("暂无 AI 配置")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(aiStore.providers.enumerated()), id: \.element.id) { index, provider in
                        Button {
                            selectedProviderID = provider.id
                        } label: {
                            ProviderRow(
                                provider: provider,
                                isActive: provider.id == aiStore.activeProviderID,
                                isSelected: provider.id == selectedProviderID
                            )
                        }
                        .buttonStyle(.plain)

                        if index < aiStore.providers.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("配置")
                .font(.system(size: 22, weight: .semibold))

            if selectedProvider == nil {
                Text("添加一个 AI 接口后开始配置。")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                VStack(spacing: 12) {
                    TextField("名称", text: $draft.name)
                        .textFieldStyle(.roundedBorder)

                    TextField("Base URL，例如 https://api.openai.com/v1", text: $draft.baseURL)
                        .textFieldStyle(.roundedBorder)

                    TextField("模型，例如 gpt-4o-mini", text: $draft.model)
                        .textFieldStyle(.roundedBorder)

                    SecureField("API Key", text: $draft.apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                Text("当前按 OpenAI-compatible Chat Completions 接口保存配置；API Key 仅保存在本机。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Button(role: .destructive) {
                        if let selectedProviderID {
                            aiStore.deleteProvider(selectedProviderID)
                        }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }

                    Spacer()

                    Button {
                        saveDraft()
                    } label: {
                        Label("保存", systemImage: "checkmark")
                    }

                    Button {
                        saveDraft()
                        if let selectedProviderID {
                            aiStore.selectProvider(selectedProviderID)
                        }
                    } label: {
                        Label("设为当前", systemImage: "checkmark.circle.fill")
                    }
                    .disabled(!draft.isReady)
                }
            }
        }
    }

    private func syncSelection() {
        if let selectedProviderID,
           aiStore.providers.contains(where: { $0.id == selectedProviderID }) {
            loadDraft()
            return
        }

        selectedProviderID = aiStore.activeProviderID ?? aiStore.providers.first?.id
        loadDraft()
    }

    private func loadDraft() {
        guard let selectedProvider else {
            draft = EditableAIProvider()
            return
        }
        draft = EditableAIProvider(provider: selectedProvider)
    }

    private func saveDraft() {
        guard let selectedProvider else {
            return
        }

        aiStore.saveProvider(
            AIProviderConfig(
                id: selectedProvider.id,
                name: draft.name,
                baseURL: draft.baseURL,
                model: draft.model,
                apiKey: draft.apiKey,
                createdAt: selectedProvider.createdAt,
                updatedAt: Date()
            )
        )
    }
}

private struct ProviderRow: View {
    let provider: AIProviderConfig
    let isActive: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(provider.name)
                        .font(.system(size: 18, weight: .semibold))

                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Text(provider.model)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isSelected {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

private struct EditableAIProvider: Hashable {
    var name = ""
    var baseURL = ""
    var model = ""
    var apiKey = ""

    init() {}

    init(provider: AIProviderConfig) {
        self.name = provider.name
        self.baseURL = provider.baseURL
        self.model = provider.model
        self.apiKey = provider.apiKey
    }

    var isReady: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
