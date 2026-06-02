import SwiftUI

struct PracticeDetailView: View {
    let item: PracticeItem
    @ObservedObject var store: PracticeStore

    var body: some View {
        VStack(spacing: 46) {
            Text(item.sourceChinese)
                .font(.system(size: 40, weight: .semibold))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 10, lineSpacing: 18) {
                ForEach(Array(item.segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case let .text(text):
                        Text(text)
                            .font(.system(size: 34, weight: .medium))
                            .fixedSize()
                    case let .blank(blank):
                        ClozeBlankField(blank: blank, store: store)
                    }
                }
            }
            .frame(maxWidth: 900)
        }
        .padding(56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
