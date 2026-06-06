import SwiftUI

struct LibraryOverviewView: View {
    @ObservedObject var store: PracticeStore

    private var totalCount: Int {
        store.librarySummaries.reduce(0) { $0 + $1.itemCount }
    }

    var body: some View {
        VStack(spacing: 42) {
            VStack(spacing: 10) {
                Text("题库")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("\(totalCount) 题")
                    .font(.system(size: 20, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                if store.librarySummaries.isEmpty {
                    Text("暂无题库")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    ForEach(Array(store.librarySummaries.enumerated()), id: \.element.id) { index, summary in
                        LibrarySummaryRow(summary: summary)

                        if index < store.librarySummaries.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxWidth: 760)
        }
        .padding(56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear {
            store.refreshLibrarySummaries()
        }
    }
}

private struct LibrarySummaryRow: View {
    let summary: PracticeLibrarySummary

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(summary.name)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.primary)

                    if summary.isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.green)
                            .help("当前使用")
                    }
                }

                Text(summary.detail)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(summary.itemCount) 题")
                .font(.system(size: 30, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 22)
    }
}
