import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryOverviewView: View {
    @ObservedObject var store: PracticeStore
    @ObservedObject var studyStore: StudyStore
    @State private var searchText = ""
    @State private var editingItemID: PracticeItem.ID?
    @State private var editChinese = ""
    @State private var editEnglish = ""
    @State private var editBlanks = ""
    @State private var deckNames: [PracticeDeck.ID: String] = [:]
    @State private var archiveMode: ArchiveMode = .export
    @State private var archivePassword = ""
    @State private var archiveError: String?
    @State private var archiveStatusMessage: String?
    @State private var isShowingArchiveSheet = false
    @State private var databaseImportingDeckID: PracticeDeck.ID?

    private enum ArchiveMode {
        case export
        case `import`

        var title: String {
            switch self {
            case .export: return "导出加密题库"
            case .import: return "导入加密题库"
            }
        }

        var buttonTitle: String {
            switch self {
            case .export: return "导出"
            case .import: return "导入"
            }
        }
    }

    private var totalCount: Int {
        store.decks.reduce(0) { $0 + $1.items.count }
    }

    private var selectedDeck: PracticeDeck? {
        store.selectedDeck
    }

    private var filteredItems: [PracticeItem] {
        guard let selectedDeck else {
            return []
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return selectedDeck.items
        }
        return selectedDeck.items.filter {
            $0.sourceChinese.lowercased().contains(query) ||
                $0.targetEnglish.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 10) {
                Text("题库")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("\(totalCount) 题")
                    .font(.system(size: 20, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 42) {
                deckList
                    .frame(width: 320)

                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        TextField("搜索当前题库", text: $searchText)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            importLocalLibraryFile()
                        } label: {
                            Label("文件入库", systemImage: "tray.and.arrow.down")
                        }
                        .help("将本地 JSON 题库文件转入 SQLite 数据库")

                        Button {
                            beginArchive(.import)
                        } label: {
                            Label("导入", systemImage: "lock.open")
                        }
                        .help("导入加密二进制题库")

                        Button {
                            beginArchive(.export)
                        } label: {
                            Label("导出", systemImage: "lock")
                        }
                        .disabled(store.decks.isEmpty)
                        .help("导出加密二进制题库")
                    }

                    if let archiveStatusMessage {
                        Text(archiveStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let archiveError {
                        Text(archiveError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    itemList
                }
                .frame(maxWidth: 620)
            }
        }
        .padding(56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear {
            refresh()
        }
        .onChange(of: studyStore.data) {
            store.refreshLibrarySummaries(studyData: studyStore.data)
        }
        .sheet(isPresented: $isShowingArchiveSheet) {
            archivePasswordSheet
        }
    }

    private var deckList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.librarySummaries) { summary in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("题库名称", text: deckNameBinding(for: summary.id))
                                .textFieldStyle(.plain)
                                .font(.system(size: 20, weight: .semibold))

                            if summary.isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .help("当前题库")
                            }
                        }

                        Text("\(summary.itemCount) 题 · 完成 \(summary.completedCount) · 易错 \(summary.mistakeCount)")
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)

                        Text(summary.detail)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)

                        HStack {
                            Button {
                                store.renameDeck(summary.id, name: deckNames[summary.id] ?? summary.name)
                            } label: {
                                Label("保存", systemImage: "checkmark")
                            }

                            Button {
                                store.selectDeck(summary.id, studyData: studyStore.data)
                                editingItemID = nil
                            } label: {
                                Label("练习", systemImage: "play")
                            }

                            if summary.isLocalFileLibrary {
                                let isImporting = databaseImportingDeckID == summary.id
                                Button {
                                    importDeckToDatabase(summary)
                                } label: {
                                    if isImporting {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "externaldrive.badge.plus")
                                    }
                                }
                                .disabled(databaseImportingDeckID != nil)
                                .help("将这个本地文件题库导入 SQLite 数据库")
                            }

                            Button(role: .destructive) {
                                store.deleteDeck(summary.id)
                                refresh()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .disabled(store.decks.count <= 1)
                            .help("删除题库")
                        }
                        .labelStyle(.iconOnly)
                    }
                    .padding(.vertical, 16)

                    Divider()
                }
            }
        }
    }

    private var itemList: some View {
        ScrollView {
            let items = filteredItems

            LazyVStack(spacing: 0) {
                if items.isEmpty {
                    Text("没有匹配题目")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ForEach(items) { item in
                        itemRow(item)

                        if editingItemID == item.id {
                            editor(for: item)
                        }

                        Divider()
                    }
                }
            }
        }
    }

    private func itemRow(_ item: PracticeItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.sourceChinese)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)

                Text(item.targetEnglish)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                beginEditing(item)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("编辑")

            Button(role: .destructive) {
                guard let deckID = selectedDeck?.id else {
                    return
                }
                store.deleteItem(item.id, in: deckID)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除")
        }
        .padding(.vertical, 12)
    }

    private func editor(for item: PracticeItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("中文提示", text: $editChinese)
                .textFieldStyle(.roundedBorder)

            TextField("目标英文", text: $editEnglish)
                .textFieldStyle(.roundedBorder)

            TextField("挖空词，用逗号分隔", text: $editBlanks)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("取消") {
                    editingItemID = nil
                }

                Spacer()

                Button {
                    guard let deckID = selectedDeck?.id else {
                        return
                    }
                    store.updateItem(
                        item.id,
                        in: deckID,
                        sourceChinese: editChinese,
                        targetEnglish: editEnglish,
                        blankText: editBlanks
                    )
                    editingItemID = nil
                } label: {
                    Label("保存题目", systemImage: "checkmark")
                }
            }
        }
        .padding(.bottom, 16)
    }

    private func beginEditing(_ item: PracticeItem) {
        editingItemID = item.id
        editChinese = item.sourceChinese
        editEnglish = item.targetEnglish
        editBlanks = item.blanks.map(\.answer).joined(separator: ", ")
    }

    private func deckNameBinding(for deckID: PracticeDeck.ID) -> Binding<String> {
        Binding(
            get: {
                deckNames[deckID] ?? store.decks.first(where: { $0.id == deckID })?.name ?? ""
            },
            set: { deckNames[deckID] = $0 }
        )
    }

    private func refresh() {
        deckNames = store.decks.reduce(into: [:]) { result, deck in
            result[deck.id] = deck.name
        }
        store.refreshLibrarySummaries(studyData: studyStore.data)
    }

    private var archivePasswordSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(archiveMode.title)
                .font(.title3)
                .fontWeight(.semibold)

            SecureField("密码", text: $archivePassword)
                .textFieldStyle(.roundedBorder)

            if let archiveError {
                Text(archiveError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("取消") {
                    isShowingArchiveSheet = false
                }

                Spacer()

                Button {
                    performArchiveAction()
                } label: {
                    Label(archiveMode.buttonTitle, systemImage: archiveMode == .export ? "lock" : "lock.open")
                }
                .disabled(archivePassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func beginArchive(_ mode: ArchiveMode) {
        archiveMode = mode
        archivePassword = ""
        archiveError = nil
        archiveStatusMessage = nil
        isShowingArchiveSheet = true
    }

    private func performArchiveAction() {
        switch archiveMode {
        case .export:
            exportEncryptedArchive()
        case .import:
            importEncryptedArchive()
        }
    }

    private func exportEncryptedArchive() {
        do {
            let data = try store.encryptedArchiveData(password: archivePassword)
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "EnglishClozeCoachLibrary.\(PracticeArchiveService.fileExtension)"
            panel.allowedContentTypes = [archiveContentType]
            guard panel.runModal() == .OK, let url = panel.url else {
                return
            }
            try data.write(to: url, options: .atomic)
            archiveStatusMessage = "已导出加密题库。"
            isShowingArchiveSheet = false
        } catch {
            archiveError = error.localizedDescription
        }
    }

    private func importEncryptedArchive() {
        do {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [archiveContentType]
            guard panel.runModal() == .OK, let url = panel.url else {
                return
            }
            let data = try Data(contentsOf: url)
            let count = try store.importEncryptedArchiveData(data, password: archivePassword)
            archiveStatusMessage = "已导入 \(count) 题。"
            isShowingArchiveSheet = false
            refresh()
        } catch {
            archiveError = error.localizedDescription
        }
    }

    private func importLocalLibraryFile() {
        archiveError = nil
        archiveStatusMessage = nil

        do {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = [.json]
            panel.message = "选择旧版 Decks.json 或 PracticeItems.json。"
            panel.prompt = "转入数据库"
            guard panel.runModal() == .OK, !panel.urls.isEmpty else {
                return
            }

            var totalCount = 0
            for url in panel.urls {
                let data = try Data(contentsOf: url)
                totalCount += try store.importLocalLibraryFileData(data, fileName: url.lastPathComponent)
            }

            if totalCount > 0 {
                archiveStatusMessage = "已转入数据库 \(totalCount) 题。"
            } else {
                archiveError = store.importError ?? "本地题库文件中没有可导入的题目。"
            }
            refresh()
        } catch {
            archiveError = error.localizedDescription
        }
    }

    private func importDeckToDatabase(_ summary: PracticeLibrarySummary) {
        guard databaseImportingDeckID == nil else {
            return
        }
        archiveError = nil
        archiveStatusMessage = "正在将「\(summary.name)」导入数据库..."
        databaseImportingDeckID = summary.id

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            let count = store.importDeckToDatabase(summary.id)
            databaseImportingDeckID = nil
            if count > 0 {
                archiveStatusMessage = "已将「\(summary.name)」导入数据库 \(count) 题。"
                refresh()
            } else {
                archiveStatusMessage = nil
                archiveError = store.importError ?? "这个题库没有新的可入库题目。"
            }
        }
    }

    private var archiveContentType: UTType {
        UTType(filenameExtension: PracticeArchiveService.fileExtension) ?? .data
    }
}
