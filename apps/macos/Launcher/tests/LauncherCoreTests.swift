import Foundation

@main
struct LauncherCoreTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Poseidon launcher tests \(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func file(_ name: String, executable: Bool = false) throws {
            let url = root.appendingPathComponent(name)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: url)
            if executable { try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        }
        for name in ["bin/CONFIG.BIN", "bin/RESOURCE.bin", "Dta/Data.pbo", "Dta/DATA3D.PBO", "fonts/CWR_body.ttf", "demo/demo.wrp"] {
            try file("install/Remastered/" + name)
        }
        guard let data = GameData.resolve(root.appendingPathComponent("install")) else { fatalError("Nested data folder was not found") }
        precondition(data.suggestedEdition == .demo)
        precondition(GameData.inspect(root) == nil)
        try file("Engine/PoseidonGameDemo", executable: true)
        let mods = root.appendingPathComponent("Mods/with spaces and 'quotes'")
        try fm.createDirectory(at: mods, withIntermediateDirectories: true)
        let request = try LaunchRequest(engineDirectory: root.appendingPathComponent("Engine"), data: data,
                                        edition: .demo, display: .fullscreen, mods: [mods])
        precondition(request.arguments.contains("borderless"))
        precondition(request.arguments[request.arguments.firstIndex(of: "--work-dir")! + 1] == data.directory.path)
        precondition(request.arguments[request.arguments.firstIndex(of: "--mod")! + 1] == mods.path)
        try file("Models/new grass.p3d")
        let model = root.appendingPathComponent("Models/new grass.p3d")
        let preview = try LaunchRequest(engineDirectory: root.appendingPathComponent("Engine"), data: data,
                                        edition: .demo, display: .windowed, previewModel: model)
        precondition(preview.arguments.contains("--viewer"))
        precondition(preview.arguments[preview.arguments.firstIndex(of: "--model")! + 1] == model.path)
        do {
            _ = try LaunchRequest(engineDirectory: root.appendingPathComponent("Engine"), data: data,
                                  edition: .demo, display: .windowed, previewModel: root)
            fatalError("A directory must not be accepted as a P3D model")
        } catch LauncherError.invalidModel { }
        do {
            _ = try LaunchRequest(engineDirectory: root.appendingPathComponent("Engine"), data: data, edition: .full, display: .windowed)
            fatalError("Missing game binary must fail before launching")
        } catch LauncherError.missingEngine { }
        let ambiguousMod = root.appendingPathComponent("Mods/ambiguous;path")
        try fm.createDirectory(at: ambiguousMod, withIntermediateDirectories: true)
        do {
            _ = try LaunchRequest(engineDirectory: root.appendingPathComponent("Engine"), data: data, edition: .demo,
                                  display: .windowed, mods: [ambiguousMod])
            fatalError("Semicolon-delimited mod paths must not be ambiguous")
        } catch LauncherError.invalidMod { }
        try fm.removeItem(at: root.appendingPathComponent("install/Remastered/fonts/CWR_body.ttf"))
        precondition(GameData.resolve(root.appendingPathComponent("install")) == nil, "Original or incomplete data must be rejected")
        print("Launcher core checks passed: data discovery, format validation, fullscreen arguments, path safety, missing binaries.")
    }
}
