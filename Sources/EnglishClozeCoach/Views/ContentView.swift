import SwiftUI

struct ContentView: View {
    @ObservedObject var store: PracticeStore
    @State private var isImporting = false

    var body: some View {
        ZStack {
            if let item = store.selectedItem {
                PracticeDetailView(item: item, store: store)
            } else {
                Text("待导入")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    isImporting = true
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .help("导入英文内容")

                Button {
                    store.goBack()
                } label: {
                    Label("上一题", systemImage: "chevron.left")
                }
                .disabled(!store.canGoBack)
                .help("上一题")

                Button {
                    store.advance()
                } label: {
                    Label("下一题", systemImage: "chevron.right")
                }
                .disabled(!store.canAdvance)
                .help("下一题")

                Button {
                    store.resetCurrentAnswers()
                } label: {
                    Label("重置", systemImage: "arrow.counterclockwise")
                }
                .disabled(store.selectedItem == nil)
                .help("重置当前题")
            }
        }
        .sheet(isPresented: $isImporting) {
            ImportView(store: store)
        }
    }
}
