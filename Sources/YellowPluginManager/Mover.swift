import AppKit

enum Mover {
    struct Result {
        var moved = 0
        var replaced = 0
        var failed: [String] = []
    }

    private static func parent(_ p: String) -> String { (p as NSString).deletingLastPathComponent }
    private static func sh(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// Moves each bundle to its destination. Tries without privileges first;
    /// whatever fails is retried in one admin-authorised batch (one password prompt).
    /// An existing copy at the destination goes to the Trash, never deleted.
    @MainActor
    static func perform(_ bundles: [PluginBundle]) -> Result {
        let fm = FileManager.default
        var result = Result()
        var privileged: [PluginBundle] = []

        for b in bundles {
            let dst = b.destination
            do {
                try fm.createDirectory(atPath: parent(dst), withIntermediateDirectories: true)
                if fm.fileExists(atPath: dst) {
                    try fm.trashItem(at: URL(fileURLWithPath: dst), resultingItemURL: nil)
                    result.replaced += 1
                }
                try fm.moveItem(atPath: b.path, toPath: dst)
                result.moved += 1
            } catch {
                privileged.append(b)
            }
        }

        guard !privileged.isEmpty else { return result }

        let stamp = Int(Date().timeIntervalSince1970)
        let trash = NSHomeDirectory() + "/.Trash"
        var lines = ["#!/bin/sh"]
        for (i, b) in privileged.enumerated() {
            let dst = b.destination
            let old = "\(trash)/\((dst as NSString).lastPathComponent) \(stamp)-\(i)"
            lines.append("mkdir -p \(sh(parent(dst)))")
            lines.append("if [ -e \(sh(dst)) ]; then mv \(sh(dst)) \(sh(old)); fi")
            lines.append("mv \(sh(b.path)) \(sh(dst))")
        }
        lines.append("exit 0")

        let script = NSTemporaryDirectory() + "ypm-\(UUID().uuidString).sh"
        defer { try? fm.removeItem(atPath: script) }
        do {
            try lines.joined(separator: "\n").write(toFile: script, atomically: true, encoding: .utf8)
        } catch {
            result.failed = privileged.map(\.name)
            return result
        }

        let source = "do shell script \"/bin/sh \(sh(script))\" with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&err)

        // Verify on disk rather than trusting the script's exit status.
        for b in privileged {
            if fm.fileExists(atPath: b.destination) && !fm.fileExists(atPath: b.path) {
                result.moved += 1
            } else {
                result.failed.append(b.name)
            }
        }
        return result
    }
}
