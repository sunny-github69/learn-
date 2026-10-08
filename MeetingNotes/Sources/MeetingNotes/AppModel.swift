import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum State: Equatable {
        case idle
        case recording(Date)
        case processing(String)
        case done(URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var models: [String] = []
    @Published private(set) var modelsError: String?

    private let recorder = Recorder()
    private var session: (dir: URL, tracks: [Track])?
    private var autoStarted = false
    private var ignoreCurrentMeeting = false
    private var missedPolls = 0

    var isRecording: Bool { if case .recording = state { return true } else { return false } }
    var canRetry: Bool { if case .failed = state, let s = session, !s.tracks.isEmpty { return true } else { return false } }
    private var isBusy: Bool {
        switch state {
        case .recording, .processing: return true
        default: return false
        }
    }

    init() {
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.pollZoom() }
        }
    }

    static var notesRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("MeetingNotes")
    }

    // MARK: Recording

    func start(auto: Bool = false) async {
        guard !isBusy else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let dir = Self.notesRoot.appendingPathComponent(formatter.string(from: Date()))
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try await recorder.start(into: dir)
            session = (dir, [])
            autoStarted = auto
            missedPolls = 0
            state = .recording(Date())
        } catch {
            ignoreCurrentMeeting = true
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        guard let dir = session?.dir, isRecording else { return }
        ignoreCurrentMeeting = true
        session = (dir, await recorder.stop())
        await process()
    }

    func retry() async { await process() }

    private func process() async {
        guard let session else { return }
        let provider = Prefs.provider
        let model = Prefs.model(for: provider)
        do {
            state = .processing("Transcribing…")
            let segments = try await Transcriber.transcribe(tracks: session.tracks, engine: Prefs.sttEngine)
            guard !segments.isEmpty else { throw AppError("No speech was detected.") }
            let transcript = Transcriber.format(segments)
            try transcript.write(to: session.dir.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)

            state = .processing("Writing notes with \(model)…")
            let notes = try await LLM.complete(provider: provider, model: model, user: transcript)
            let file = session.dir.appendingPathComponent("notes.md")
            try notes.write(to: file, atomically: true, encoding: .utf8)

            // Raw audio is only kept when something failed, so it can be retried.
            session.tracks.flatMap(\.chunks).forEach { try? FileManager.default.removeItem(at: $0.url) }
            self.session = nil
            state = .done(file)
        } catch {
            state = .failed("\(error.localizedDescription) Audio kept in \(session.dir.lastPathComponent).")
        }
    }

    // MARK: Zoom auto-detection

    /// Zoom spawns a "CptHost" helper process for as long as a meeting is running.
    private func pollZoom() async {
        guard Prefs.autoDetectZoom else { return }
        let inMeeting = await Task.detached { () -> Bool in
            let pgrep = Process()
            pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            pgrep.arguments = ["-x", "CptHost"]
            pgrep.standardOutput = FileHandle.nullDevice
            do {
                try pgrep.run()
                pgrep.waitUntilExit()
                return pgrep.terminationStatus == 0
            } catch { return false }
        }.value

        if !inMeeting { ignoreCurrentMeeting = false }
        if isRecording {
            guard autoStarted else { return }
            missedPolls = inMeeting ? 0 : missedPolls + 1
            if missedPolls >= 2 { await stop() }
        } else if inMeeting && !ignoreCurrentMeeting {
            await start(auto: true)
        }
    }

    // MARK: Settings helpers

    /// Refreshes the model list for the provider and returns it.
    func refreshModels(for provider: Provider) async {
        modelsError = nil
        do { models = try await LLM.models(for: provider) } catch {
            models = []
            modelsError = error.localizedDescription
        }
    }
}
