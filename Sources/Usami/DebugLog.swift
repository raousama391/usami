import Foundation

/// Tiny file logger (~/Library/Logs/Usami.log). Logs only metadata — never the selected text.
enum DebugLog {
    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
        return dir.appendingPathComponent("Usami.log")
    }()
    private static let queue = DispatchQueue(label: "usami.debuglog")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        queue.async {
            let line = "\(formatter.string(from: Date())) \(message)\n"
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
