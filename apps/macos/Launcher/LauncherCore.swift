import Foundation

enum GameEdition: String, CaseIterable, Identifiable {
    case demo = "Demo"
    case full = "Full game"
    var id: Self { self }
    var executable: String { self == .demo ? "PoseidonGameDemo" : "PoseidonGame" }
}

enum DisplayMode: String, CaseIterable, Identifiable {
    case fullscreen = "Fullscreen"
    case windowed = "Windowed"
    var id: Self { self }
    var argument: String { self == .fullscreen ? "borderless" : "windowed" }
}

struct GameData: Equatable {
    let directory: URL
    let suggestedEdition: GameEdition

    // Read names case-insensitively even on a case-sensitive APFS volume.
    static func child(_ root: URL, _ path: String) -> URL? {
        var current = root
        for component in path.split(separator: "/") {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: current, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ), let found = children.first(where: { $0.lastPathComponent.caseInsensitiveCompare(String(component)) == .orderedSame }) else {
                return nil
            }
            current = found
        }
        return current
    }

    static func inspect(_ directory: URL) -> GameData? {
        let required = ["BIN/config.bin", "BIN/resource.bin", "DTA/data.pbo", "DTA/data3d.pbo", "fonts/cwr_body.ttf"]
        guard required.allSatisfy({ relative in
            guard let file = child(directory, relative) else { return false }
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            return values?.isRegularFile == true && (values?.fileSize ?? 0) > 0 && FileManager.default.isReadableFile(atPath: file.path)
        }) else { return nil }
        let isDemo = child(directory, "demo/demo.wrp") != nil
        return GameData(directory: directory.standardizedFileURL, suggestedEdition: isDemo ? .demo : .full)
    }

    static func resolve(_ chosen: URL) -> GameData? {
        // Accept the data folder itself, a Steam install, or a source checkout.
        let relatives = ["", "Remastered", "Remaster", "Demo", "packages/Demo", "packages/Remastered", "packages/Remaster"]
        for relative in relatives {
            let candidate = relative.isEmpty ? chosen : chosen.appendingPathComponent(relative)
            if let data = inspect(candidate) { return data }
        }
        return nil
    }

    static func discover(bundle: URL, home: URL, savedPath: String?) -> GameData? {
        var roots: [URL] = []
        if let savedPath, !savedPath.isEmpty { roots.append(URL(fileURLWithPath: savedPath)) }
        var parent = bundle.deletingLastPathComponent()
        for _ in 0..<3 {
            roots.append(parent.appendingPathComponent("GameData"))
            roots.append(parent)
            parent.deleteLastPathComponent()
        }
        let steam = home.appendingPathComponent("Library/Application Support/Steam")
        var libraries = [steam]
        let libraryFile = steam.appendingPathComponent("steamapps/libraryfolders.vdf")
        if let contents = try? String(contentsOf: libraryFile, encoding: .utf8),
           let regex = try? NSRegularExpression(pattern: #""path"\s*"((?:\\.|[^"\\])*)""#) {
            for match in regex.matches(in: contents, range: NSRange(contents.startIndex..., in: contents)) {
                if let range = Range(match.range(at: 1), in: contents) {
                    let path = String(contents[range]).replacingOccurrences(of: "\\\\", with: "\\")
                    libraries.append(URL(fileURLWithPath: path))
                }
            }
        }
        for library in libraries {
            let common = library.appendingPathComponent("steamapps/common")
            if let entries = try? FileManager.default.contentsOfDirectory(at: common, includingPropertiesForKeys: nil) {
                roots.append(contentsOf: entries.filter { $0.lastPathComponent.lowercased().contains("cold war assault") })
            }
        }
        for root in roots { if let data = resolve(root) { return data } }
        return nil
    }
}

enum LauncherError: LocalizedError {
    case missingEngine(String)
    case invalidMod(String)
    case invalidModel
    var errorDescription: String? {
        switch self {
        case .missingEngine(let name): return "The app is missing \(name). Rebuild or reinstall the launcher."
        case .invalidMod(let path): return "Choose a readable mod folder whose path does not contain a semicolon: \(path)"
        case .invalidModel: return "Choose a readable P3D model file."
        }
    }
}

struct LaunchRequest {
    let executable: URL
    let arguments: [String]
    let workingDirectory: URL

    init(engineDirectory: URL, data: GameData, edition: GameEdition, display: DisplayMode, mods: [URL] = [], previewModel: URL? = nil, check: Bool = false) throws {
        executable = engineDirectory.appendingPathComponent(edition.executable)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw LauncherError.missingEngine(edition.executable) }
        var args = ["--work-dir", data.directory.path, "--display-mode", display.argument, "--no-strict"]
        for mod in mods {
            let values = try? mod.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true, FileManager.default.isReadableFile(atPath: mod.path), !mod.path.contains(";") else {
                throw LauncherError.invalidMod(mod.path)
            }
        }
        if !mods.isEmpty { args += ["--mod", mods.map(\.path).joined(separator: ";")] }
        if let previewModel {
            let values = try? previewModel.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true, previewModel.pathExtension.lowercased() == "p3d",
                  FileManager.default.isReadableFile(atPath: previewModel.path) else { throw LauncherError.invalidModel }
            args += ["--viewer", "--model", previewModel.path, "--no-splash"]
        }
        if check { args += ["--check", "--no-splash"] }
        arguments = args
        workingDirectory = data.directory
    }
}
