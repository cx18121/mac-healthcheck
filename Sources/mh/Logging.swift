import Foundation

enum AuditLogger {
    static let logDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: ".local/state/mh", directoryHint: .isDirectory)
    }()
    static var logFile: URL { logDir.appending(path: "log.jsonl") }
    static var errorFile: URL { logDir.appending(path: "error.log") }
    static var sessionsFile: URL { logDir.appending(path: "sessions.jsonl") }

    static func ensureDir() throws {
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    }

    static func append(_ entry: [String: Any], to file: URL) throws {
        try ensureDir()
        let data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.write(Data([0x0A]))   // newline
            try? handle.close()
        } else {
            var initial = data
            initial.append(0x0A)
            try initial.write(to: file)
        }
    }
}
