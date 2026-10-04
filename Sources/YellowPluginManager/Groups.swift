import Foundation

/// One membership rule. A plugin matching any rule of a group belongs to it.
struct GroupRule: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case nameStarts = "Name starts with"
        case nameContains = "Name contains"
        case vendorIs = "Vendor is"
    }

    var id = UUID()
    var kind: Kind
    var text: String

    func matches(_ n: Node) -> Bool {
        let t = text.lowercased()
        guard !t.isEmpty else { return false }
        switch kind {
        case .nameStarts: return n.name.lowercased().hasPrefix(t)
        case .nameContains: return n.name.lowercased().contains(t)
        case .vendorIs: return n.vendor.lowercased() == t
        }
    }
}

/// A named set of plugins that is switched Used / Unused as a whole.
/// Members come from rules and from plugins added by hand.
struct PluginGroup: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var rules: [GroupRule] = []
    var manual: [String] = []
    /// Plugins a rule would match but that were taken out of the group by hand.
    var excluded: [String]? = nil
    /// Last state the group was switched to; nil until it is switched the first time.
    var enabled: Bool? = nil
}

enum GroupStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YellowPluginManager")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("groups.json")
    }

    static func load() -> [PluginGroup] {
        if let data = try? Data(contentsOf: url),
           let groups = try? JSONDecoder().decode([PluginGroup].self, from: data) {
            return groups
        }
        // First run. "UAD " (with the space) never matches native UADx bundles ("uaudio_…").
        return [
            PluginGroup(name: "UAD DSP", rules: [GroupRule(kind: .nameStarts, text: "UAD ")]),
            PluginGroup(name: "SPARTA", rules: [GroupRule(kind: .nameStarts, text: "sparta_")]),
            PluginGroup(name: "COMPASS", rules: [GroupRule(kind: .nameStarts, text: "compass_")]),
        ]
    }

    static func save(_ groups: [PluginGroup]) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(groups) { try? data.write(to: url, options: .atomic) }
    }
}
