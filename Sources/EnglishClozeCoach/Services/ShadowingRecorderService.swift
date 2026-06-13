import AVFoundation
import Foundation

@MainActor
final class ShadowingRecorderService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false
    @Published private(set) var hasRecording = false
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var errorMessage: String?

    private let fileManager: FileManager
    private var currentItemID: PracticeItem.ID?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var playbackTimer: Timer?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func prepare(for itemID: PracticeItem.ID) {
        guard currentItemID != itemID else {
            refreshRecordingState()
            return
        }

        stopRecording()
        stopPlayback()
        currentItemID = itemID
        elapsedTime = 0
        errorMessage = nil
        refreshRecordingState()
    }

    func startRecording(for itemID: PracticeItem.ID) async {
        guard !isRecording else {
            return
        }

        stopPlayback()
        currentItemID = itemID
        errorMessage = nil

        guard await microphoneAccessGranted() else {
            errorMessage = "无法使用麦克风，请在系统设置里允许 whatever 访问麦克风。"
            return
        }

        do {
            let url = try recordingURL(for: itemID)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.prepareToRecord()
            recorder.record()
            self.recorder = recorder
            isRecording = true
            hasRecording = false
            elapsedTime = 0
            startRecordingTimer()
        } catch {
            errorMessage = "无法开始录音：\(error.localizedDescription)"
        }
    }

    func stopRecording() {
        guard isRecording else {
            return
        }

        recorder?.stop()
        recorder = nil
        isRecording = false
        stopRecordingTimer()
        refreshRecordingState()
    }

    func playRecording() {
        guard !isRecording else {
            return
        }

        stopPlayback()
        guard let currentItemID,
              let url = try? recordingURL(for: currentItemID),
              fileManager.fileExists(atPath: url.path) else {
            errorMessage = "还没有可回放的录音。"
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            self.player = player
            isPlaying = true
            errorMessage = nil
            startPlaybackTimer()
        } catch {
            errorMessage = "无法回放录音：\(error.localizedDescription)"
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        stopPlaybackTimer()
    }

    func deleteRecording() {
        stopRecording()
        stopPlayback()

        guard let currentItemID,
              let url = try? recordingURL(for: currentItemID) else {
            return
        }

        try? fileManager.removeItem(at: url)
        elapsedTime = 0
        refreshRecordingState()
    }

    private func microphoneAccessGranted() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func recordingURL(for itemID: PracticeItem.ID) throws -> URL {
        let directory = try recordingsDirectory()
        let safeItemID = itemID.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]"#,
            with: "_",
            options: .regularExpression
        )
        return directory.appendingPathComponent("\(safeItemID).m4a")
    }

    private func recordingsDirectory() throws -> URL {
        let directory = ApplicationSupport.directory(fileManager: fileManager)
            .appendingPathComponent("Recordings", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func refreshRecordingState() {
        guard let currentItemID,
              let url = try? recordingURL(for: currentItemID) else {
            hasRecording = false
            return
        }
        hasRecording = fileManager.fileExists(atPath: url.path)
    }

    private func startRecordingTimer() {
        stopRecordingTimer()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else {
                    return
                }
                self.elapsedTime = recorder.currentTime
            }
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }
                if self.player?.isPlaying != true {
                    self.stopPlayback()
                }
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
}
