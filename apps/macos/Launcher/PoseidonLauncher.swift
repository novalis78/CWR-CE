import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LauncherModel: ObservableObject {
    @Published var data: GameData?
    @Published var edition: GameEdition = .demo
    @Published var display: DisplayMode = .fullscreen
    @Published var mods: [URL] = []
    @Published var running = false
    @Published var error: String?
    @Published var lastLog: URL?
    private var process: Process?
    private var logHandle: FileHandle?
    private let defaults = UserDefaults.standard

    var engineDirectory: URL { Bundle.main.resourceURL!.appendingPathComponent("Engine") }
    var logDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Poseidon Launcher/Logs")
    }

    init() {
        data = GameData.discover(bundle: Bundle.main.bundleURL, home: FileManager.default.homeDirectoryForCurrentUser,
                                 savedPath: defaults.string(forKey: "gameDataPath"))
        if let data { edition = data.suggestedEdition }
        if let raw = defaults.string(forKey: "displayMode"), let saved = DisplayMode(rawValue: raw) { display = saved }
        mods = (defaults.stringArray(forKey: "modPaths") ?? []).map { URL(fileURLWithPath: $0) }
        if let data { defaults.set(data.directory.path, forKey: "gameDataPath") }
    }

    func chooseData() {
        let panel = NSOpenPanel()
        panel.title = "Choose game data"
        panel.message = "Choose the Remastered or Demo folder containing BIN, DTA, and fonts."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = data?.directory
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        guard let found = GameData.resolve(selected) else {
            error = "This folder does not contain complete Remastered game data. Choose the installed Demo or Remastered folder, including BIN, DTA, and fonts."
            return
        }
        data = found
        edition = found.suggestedEdition
        defaults.set(found.directory.path, forKey: "gameDataPath")
    }

    func addMods() {
        let panel = NSOpenPanel()
        panel.title = "Add mod folders"
        panel.message = "Choose mod folders containing AddOns. They load in the order shown."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !mods.contains(url) { mods.append(url) }
        saveMods()
    }

    func removeMod(_ url: URL) { mods.removeAll { $0 == url }; saveMods() }
    private func saveMods() { defaults.set(mods.map(\.path), forKey: "modPaths") }

    func previewModel() {
        let panel = NSOpenPanel()
        panel.title = "Preview a P3D model"
        panel.message = "Choose a model to open in the engine viewer. Add its mod folder first if it uses custom textures."
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "p3d") ?? .data]
        guard panel.runModal() == .OK, let model = panel.url else { return }
        play(previewModel: model)
    }

    func play(previewModel: URL? = nil) {
        guard !running, let data else { return }
        do {
            let request = try LaunchRequest(engineDirectory: engineDirectory, data: data, edition: edition, display: display, mods: mods, previewModel: previewModel)
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let log = logDirectory.appendingPathComponent("game-\(stamp)-\(UUID().uuidString.prefix(6)).log")
            guard FileManager.default.createFile(atPath: log.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let output = try FileHandle(forWritingTo: log)
            let child = Process()
            child.executableURL = request.executable
            child.arguments = request.arguments
            child.currentDirectoryURL = request.workingDirectory
            child.standardOutput = output
            child.standardError = output
            child.terminationHandler = { [weak self] completed in
                let status = completed.terminationStatus
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.running = false
                    self.process = nil
                    try? self.logHandle?.close()
                    self.logHandle = nil
                    if status != 0 { self.error = "The game stopped with exit code \(status). Open the latest log for details." }
                    NSApp.unhide(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first(where: { $0.canBecomeMain })?.deminiaturize(nil)
                }
            }
            do { try child.run() } catch { try? output.close(); throw error }
            process = child
            logHandle = output
            lastLog = log
            running = true
            defaults.set(display.rawValue, forKey: "displayMode")
            NSApp.keyWindow?.miniaturize(nil)
        } catch { self.error = error.localizedDescription }
    }

    func openLogs() {
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        if let lastLog { NSWorkspace.shared.activateFileViewerSelecting([lastLog]) }
        else { NSWorkspace.shared.open(logDirectory) }
    }

    func openGuide() {
        if let guide = Bundle.main.url(forResource: "Creator Guide", withExtension: "html") { NSWorkspace.shared.open(guide) }
    }
}

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    private let accent = Color(red: 0.30, green: 0.43, blue: 0.34)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 15) {
                Image(systemName: "mountain.2.fill").font(.system(size: 34)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Poseidon").font(.system(size: 29, weight: .semibold, design: .rounded))
                    Text("Community game launcher").foregroundStyle(.secondary)
                }
                Spacer()
                Text("macOS").font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(model.data == nil ? "Choose your game data" : "Game data ready",
                              systemImage: model.data == nil ? "folder" : "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(model.data == nil ? .primary : accent)
                        Spacer()
                        Button("Choose Folder…", action: model.chooseData).disabled(model.running)
                    }
                    if let data = model.data {
                        Text(data.directory.path).font(.callout).foregroundStyle(.secondary)
                            .lineLimit(2).textSelection(.enabled)
                    } else {
                        Text("Select the free Demo or your Remastered installation. Game data is installed separately.")
                            .font(.callout).foregroundStyle(.secondary)
                        Link("Get the free demo on Steam", destination: URL(string: "https://store.steampowered.com/app/4819000/")!)
                    }
                }.padding(10)
            }
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Edition").font(.headline)
                    Picker("Edition", selection: $model.edition) {
                        ForEach(GameEdition.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().disabled(model.running)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Display").font(.headline)
                    Picker("Display", selection: $model.display) {
                        ForEach(DisplayMode.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().disabled(model.running)
                }
            }
            Text("Adjust resolution and graphics quality in the game’s Display and Graphics options.")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Mods").font(.headline)
                    Spacer()
                    Button("Add…", action: model.addMods).disabled(model.running)
                }
                if model.mods.isEmpty {
                    Text("No additional mods selected.").font(.callout).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(model.mods, id: \.path) { mod in
                                HStack {
                                    Image(systemName: "shippingbox")
                                    Text(mod.lastPathComponent).lineLimit(1).help(mod.path)
                                    Spacer()
                                    Button { model.removeMod(mod) } label: { Image(systemName: "minus.circle") }
                                        .buttonStyle(.borderless).help("Remove \(mod.lastPathComponent)").disabled(model.running)
                                }
                            }
                        }
                    }.frame(maxHeight: 80)
                }
            }
            Divider()
            HStack {
                Button("Creator Guide", action: model.openGuide)
                Button("Preview Model…", action: model.previewModel).disabled(model.data == nil || model.running)
                Button("Logs", action: model.openLogs)
                Spacer()
                if model.running { ProgressView().controlSize(.small) }
                Button(action: { model.play() }) {
                    Label(model.running ? "Game is running" : "Play", systemImage: "play.fill")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent).tint(accent).controlSize(.large)
                .keyboardShortcut(.defaultAction).disabled(model.data == nil || model.running)
            }
        }
        .padding(28).frame(width: 660)
        .alert("Unable to continue", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
            Button("Open Logs") { model.openLogs(); model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

@main
struct PoseidonLauncherApp: App {
    @StateObject private var model = LauncherModel()

    init() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--check-data"), args.indices.contains(index + 1) {
            let path = URL(fileURLWithPath: args[index + 1])
            guard let data = GameData.resolve(path) else { fputs("Game data is incomplete or incompatible.\n", stderr); exit(1) }
            print("\(data.suggestedEdition.rawValue): \(data.directory.path)")
            exit(0)
        }
        if let index = args.firstIndex(of: "--set-data"), args.indices.contains(index + 1),
           let data = GameData.resolve(URL(fileURLWithPath: args[index + 1])) {
            UserDefaults.standard.set(data.directory.path, forKey: "gameDataPath")
        }
    }

    var body: some Scene {
        Window("Poseidon Launcher", id: "launcher") {
            LauncherView(model: model)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) { Button("Creator Guide", action: model.openGuide) }
        }
    }
}
