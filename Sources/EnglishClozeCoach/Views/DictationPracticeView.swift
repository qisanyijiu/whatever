import SwiftUI

struct DictationPracticeView: View {
    let item: PracticeItem
    let speechService: SpeechService
    @State private var typedSentence = ""
    @State private var isShowingAnswer = false

    var body: some View {
        VStack(spacing: 34) {
            VStack(spacing: 12) {
                Text("听写")
                    .font(.system(size: 42, weight: .semibold))

                Text(item.sourceChinese)
                    .font(.system(size: 28, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextEditor(text: $typedSentence)
                .font(.system(size: 24, weight: .medium))
                .frame(maxWidth: 760, minHeight: 160)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator, lineWidth: 1)
                }

            HStack(spacing: 14) {
                Button {
                    speechService.speak(item.targetEnglish)
                } label: {
                    Label("朗读", systemImage: "speaker.wave.2")
                }

                Button {
                    isShowingAnswer.toggle()
                } label: {
                    Label(isShowingAnswer ? "隐藏答案" : "显示答案", systemImage: "eye")
                }
            }

            if isShowingAnswer {
                Text(item.targetEnglish)
                    .font(.system(size: 24, weight: .medium))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .frame(maxWidth: 760)
            }
        }
        .padding(56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear {
            speechService.speak(item.targetEnglish)
        }
    }
}
