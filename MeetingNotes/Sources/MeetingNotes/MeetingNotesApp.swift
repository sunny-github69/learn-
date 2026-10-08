import SwiftUI

@main
struct MeetingNotesApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(model)
        } label: {
            Image(systemName: model.isRecording ? "record.circle.fill" : "waveform.circle")
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView().environmentObject(model)
        }
        .windowResizability(.contentSize)
    }
}

struct MenuView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("autoDetectZoom") private var autoDetectZoom = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            status
            Toggle("Auto-record when a Zoom meeting starts", isOn: $autoDetectZoom)
            Divider()
            HStack {
                Button("Notes folder") {
                    try? FileManager.default.createDirectory(at: AppModel.notesRoot, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(AppModel.notesRoot)
                }
                Button("Settings…") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    @ViewBuilder private var status: some View {
        switch model.state {
        case .idle:
            Button("Start recording") { Task { await model.start() } }.buttonStyle(.borderedProminent)
        case .recording(let since):
            Label { Text(since, style: .timer) } icon: { Image(systemName: "record.circle.fill").foregroundStyle(.red) }
            Button("Stop & write notes") { Task { await model.stop() } }.buttonStyle(.borderedProminent)
        case .processing(let message):
            HStack { ProgressView().controlSize(.small); Text(message) }
        case .done(let file):
            Label("Notes ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            HStack {
                Button("Open notes") { NSWorkspace.shared.open(file) }.buttonStyle(.borderedProminent)
                Button("New recording") { Task { await model.start() } }
            }
        case .failed(let message):
            Text(message).foregroundStyle(.red).font(.caption).fixedSize(horizontal: false, vertical: true)
            HStack {
                if model.canRetry { Button("Retry") { Task { await model.retry() } } }
                Button("New recording") { Task { await model.start() } }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("llmProvider") private var providerRaw = Provider.anthropic.rawValue
    @AppStorage("sttEngine") private var sttRaw = STTEngine.local.rawValue
    @AppStorage("whisperModelPath") private var whisperPath = Prefs.defaultWhisperModel
    @State private var apiKey = ""
    @State private var selectedModel = ""

    private var provider: Provider { Provider(rawValue: providerRaw) ?? .anthropic }

    var body: some View {
        Form {
            Section("Notes AI") {
                Picker("Provider", selection: $providerRaw) {
                    ForEach(Provider.allCases) { Text($0.title).tag($0.rawValue) }
                }
                SecureField("API key", text: $apiKey)
                HStack {
                    Picker("Model", selection: $selectedModel) {
                        ForEach(model.models, id: \.self) { Text($0).tag($0) }
                    }
                    Button("Refresh") { Task { await reloadModels() } }
                }
                if let error = model.modelsError { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Section("Transcription") {
                Picker("Engine", selection: $sttRaw) {
                    ForEach(STTEngine.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if sttRaw == STTEngine.local.rawValue {
                    TextField("Whisper model file", text: $whisperPath)
                } else {
                    Text("Uses your OpenAI API key.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .task { await load() }
        .onChange(of: providerRaw) { _ in Task { await load() } }
        .onChange(of: apiKey) { Keychain.set($0, for: providerRaw) }
        .onChange(of: selectedModel) { UserDefaults.standard.set($0, forKey: "model.\(providerRaw)") }
    }

    private func load() async {
        apiKey = Keychain.get(providerRaw) ?? ""
        selectedModel = Prefs.model(for: provider)
        await reloadModels()
    }

    private func reloadModels() async {
        await model.refreshModels(for: provider)
        if !model.models.contains(selectedModel), let first = model.models.first { selectedModel = first }
    }
}
