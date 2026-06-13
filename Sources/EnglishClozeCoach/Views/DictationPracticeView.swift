import Foundation
import SwiftUI

struct DictationPracticeView: View {
    let item: PracticeItem
    let speechService: SpeechService
    @ObservedObject var studyStore: StudyStore
    let onCompleted: () -> Void
    @StateObject private var recorder = ShadowingRecorderService()
    @StateObject private var focusAdvancer = ClozeBlankFocusAdvanceController()
    @StateObject private var timingTracker = BlankInputTimingTracker()
    @State private var answers: [ClozeBlank.ID: String] = [:]
    @State private var isShowingAnswer = false
    @State private var recordedWrongAnswerKeys = Set<String>()
    @State private var completionTask: Task<Void, Never>?
    @FocusState private var focusedBlankID: ClozeBlank.ID?

    var body: some View {
        VStack(spacing: 36) {
            VStack(spacing: 12) {
                Text(item.sourceChinese)
                    .font(.system(size: 40, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FlowLayout(spacing: 10, lineSpacing: 18) {
                ForEach(Array(dictationSegments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case let .text(text):
                        Text(text)
                            .font(.system(size: 34, weight: .medium))
                            .fixedSize()
                    case let .blank(blank):
                        let state = answerState(for: blank, in: answers)
                        ClozeBlankInputField(
                            blank: blank,
                            text: answerBinding(for: blank),
                            state: state,
                            showsAnswer: isShowingAnswer,
                            isReadOnly: state == .correct,
                            focusedBlankID: $focusedBlankID
                        )
                    }
                }
            }
            .frame(maxWidth: 900)

            HStack(spacing: 14) {
                Button {
                    speechService.speak(item.targetEnglish)
                } label: {
                    Label("朗读", systemImage: AppToolbarSymbols.speak)
                }

                Button {
                    if !isShowingAnswer {
                        studyStore.recordHintViewed(item: item)
                    }
                    isShowingAnswer.toggle()
                } label: {
                    Label(isShowingAnswer ? "隐藏答案" : "显示答案", systemImage: AppToolbarSymbols.hint)
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
            focusFirstBlank()
        }
        .onChange(of: item.id) {
            recorder.prepare(for: item.id)
            answers = [:]
            isShowingAnswer = false
            recordedWrongAnswerKeys = []
            timingTracker.reset()
            completionTask?.cancel()
            completionTask = nil
            focusAdvancer.cancel()
            focusFirstBlank()
        }
        .onChange(of: focusedBlankID) {
            timingTracker.focusChanged(to: focusedBlankID)
        }
        .onDisappear {
            completionTask?.cancel()
            focusAdvancer.cancel()
            recorder.stopRecording()
            recorder.stopPlayback()
        }
    }

    private var dictationSegments: [DictationSegment] {
        Self.dictationSegments(from: item.targetEnglish, itemID: item.id)
    }

    private var dictationBlanks: [ClozeBlank] {
        dictationSegments.compactMap { segment in
            if case let .blank(blank) = segment {
                return blank
            }
            return nil
        }
    }

    private func answerBinding(for blank: ClozeBlank) -> Binding<String> {
        Binding(
            get: { answers[blank.id] ?? "" },
            set: { updateAnswer($0, for: blank) }
        )
    }

    private func updateAnswer(_ value: String, for blank: ClozeBlank) {
        let sanitizedValue = DictationAnswerRules.sanitizedInput(value)
        var updatedAnswers = answers
        updatedAnswers[blank.id] = sanitizedValue
        answers = updatedAnswers

        let state = answerState(for: blank, in: updatedAnswers)
        timingTracker.inputChanged(blank: blank, text: sanitizedValue, isCorrect: state == .correct) {
            secondsPerLetter,
            wordStartDelay in
            studyStore.recordInputTiming(
                item: item,
                secondsPerLetter: secondsPerLetter,
                wordStartDelay: wordStartDelay
            )
        }
        recordSpellingErrorIfNeeded(blank: blank, answer: sanitizedValue, state: state)

        if state == .correct {
            focusAdvancer.schedule(
                after: blank,
                expectedAnswer: sanitizedValue,
                blanks: dictationBlanks,
                currentFocusedID: { focusedBlankID },
                currentAnswer: { answers[$0.id] ?? "" },
                isCorrect: { answerState(for: $0, in: answers) == .correct },
                focus: { focusedBlankID = $0 }
            )
        } else {
            focusAdvancer.cancel()
        }
        syncCompletionState(answers: updatedAnswers)
    }

    private func recordSpellingErrorIfNeeded(
        blank: ClozeBlank,
        answer: String,
        state: ClozeBlankInputState
    ) {
        guard state == .incorrect,
              answer.count >= DictationAnswerRules.sanitizedInput(blank.answer).count else {
            return
        }

        let key = "\(blank.id)-\(answer.lowercased())"
        guard !recordedWrongAnswerKeys.contains(key) else {
            return
        }
        recordedWrongAnswerKeys.insert(key)
        studyStore.recordMistake(item: item, blank: blank, wrongAnswer: answer)
    }

    private func answerState(
        for blank: ClozeBlank,
        in answers: [ClozeBlank.ID: String]
    ) -> ClozeBlankInputState {
        let answer = answers[blank.id] ?? ""
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .idle
        }
        return DictationAnswerRules.isExactMatch(answer, answer: blank.answer) ? .correct : .incorrect
    }

    private func focusFirstBlank() {
        focusedBlankID = dictationBlanks.first?.id
        timingTracker.focusChanged(to: focusedBlankID)
    }

    private func syncCompletionState(answers: [ClozeBlank.ID: String]) {
        guard isSentenceCompleted(answers: answers) else {
            completionTask?.cancel()
            completionTask = nil
            return
        }
        guard completionTask == nil else {
            return
        }

        completionTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard isSentenceCompleted(answers: self.answers) else {
                    completionTask = nil
                    return
                }

                focusedBlankID = nil
                completionTask = nil
                onCompleted()
            }
        }
    }

    private func isSentenceCompleted(answers: [ClozeBlank.ID: String]) -> Bool {
        let blanks = dictationBlanks
        return !blanks.isEmpty && blanks.allSatisfy { blank in
            answerState(for: blank, in: answers) == .correct
        }
    }

    private static let dictationWordRegex = try! NSRegularExpression(
        pattern: #"[A-Za-z0-9]+(?:['’][A-Za-z0-9]+)?"#
    )

    private static func dictationSegments(from sentence: String, itemID: PracticeItem.ID) -> [DictationSegment] {
        let nsSentence = sentence as NSString
        let sentenceRange = NSRange(location: 0, length: nsSentence.length)
        let matches = dictationWordRegex.matches(in: sentence, range: sentenceRange)
        guard !matches.isEmpty else {
            return [.text(sentence)]
        }

        var cursor = 0
        var wordIndex = 1
        var segments: [DictationSegment] = []

        for match in matches {
            if match.range.location > cursor {
                let textRange = NSRange(location: cursor, length: match.range.location - cursor)
                segments.append(.text(nsSentence.substring(with: textRange)))
            }

            let answer = nsSentence.substring(with: match.range)
            segments.append(.blank(ClozeBlank(id: "\(itemID)-dictation-\(wordIndex)", answer: answer)))
            cursor = match.range.location + match.range.length
            wordIndex += 1
        }

        if cursor < nsSentence.length {
            segments.append(.text(nsSentence.substring(from: cursor)))
        }

        return segments
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
                    .frame(minWidth: 92, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if let errorMessage = recorder.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 760, alignment: .center)
            }
        }
        .frame(maxWidth: 760, alignment: .center)
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

private enum DictationSegment: Hashable {
    case text(String)
    case blank(ClozeBlank)
}
