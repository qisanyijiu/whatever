import SwiftUI

struct DictationPracticeView: View {
    let item: PracticeItem
    let speechService: SpeechService
    @StateObject private var recorder = ShadowingRecorderService()
    @State private var typedSentence = ""
    @State private var isShowingAnswer = false

    var body: some View {
        VStack(spacing: 30) {
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

            shadowingControls

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
            recorder.prepare(for: item.id)
            speechService.speak(item.targetEnglish)
        }
        .onChange(of: item.id) {
            recorder.prepare(for: item.id)
            typedSentence = ""
            isShowingAnswer = false
        }
        .onDisappear {
            recorder.stopRecording()
            recorder.stopPlayback()
        }
    }

    private var shadowingControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Button {
                    if recorder.isRecording {
                        recorder.stopRecording()
                    } else {
                        Task {
                            await recorder.startRecording(for: item.id)
                        }
                    }
                } label: {
                    Label(recorder.isRecording ? "停止" : "录音", systemImage: recorder.isRecording ? "stop.circle" : "record.circle")
                }
                .tint(recorder.isRecording ? .red : nil)

                Button {
                    if recorder.isPlaying {
                        recorder.stopPlayback()
                    } else {
                        recorder.playRecording()
                    }
                } label: {
                    Label(recorder.isPlaying ? "停止回放" : "回放", systemImage: recorder.isPlaying ? "stop.circle" : "play.circle")
                }
                .disabled(!recorder.hasRecording || recorder.isRecording)

                Button {
                    recorder.deleteRecording()
                } label: {
                    Label("重录", systemImage: "arrow.counterclockwise")
                }
                .disabled(!recorder.hasRecording || recorder.isRecording)

                Text(recordingStatusText)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 92, alignment: .leading)
            }

            if let errorMessage = recorder.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 760, alignment: .leading)
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    private var recordingStatusText: String {
        if recorder.isRecording {
            return "录音中 \(formattedDuration(recorder.elapsedTime))"
        }
        if recorder.isPlaying {
            return "回放中"
        }
        if recorder.hasRecording {
            return "已录音"
        }
        return "未录音"
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded(.down)))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
