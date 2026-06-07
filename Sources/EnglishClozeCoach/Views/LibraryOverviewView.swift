import SwiftUI

struct LibraryOverviewView: View {
    @ObservedObject var store: PracticeStore
    @ObservedObject var studyStore: StudyStore
    @State private var searchText = ""
    @State private var editingItemID: PracticeItem.ID?
    @State private var editChinese = ""
    @State private var editEnglish = ""
    @State private var editBlanks = ""
    @State private var deckNames: [PracticeDeck.ID: String] = [:]

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
                    TextField("搜索当前题库", text: $searchText)
                        .textFieldStyle(.roundedBorder)

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
    }

    private var deckList: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.librarySummaries.enumerated()), id: \.element.id) { index, summary in
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
                            store.selectDeck(summary.id)
                            editingItemID = nil
                        } label: {
                            Label("练习", systemImage: "play")
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

                if index < store.librarySummaries.count - 1 {
                    Divider()
                }
            }
        }
    }

    private var itemList: some View {
        ScrollView {
            VStack(spacing: 0) {
                if filteredItems.isEmpty {
                    Text("没有匹配题目")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                        itemRow(item)

                        if editingItemID == item.id {
                            editor(for: item)
                        }

                        if index < filteredItems.count - 1 {
                            Divider()
                        }
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
}
