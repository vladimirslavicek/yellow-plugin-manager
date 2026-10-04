import Foundation

enum PluginFormat: String, CaseIterable, Identifiable {
    case vst2 = "VST2", vst3 = "VST3", au = "AU", aax = "AAX", clap = "CLAP"

    var id: String { rawValue }

    var ext: String {
        switch self {
        case .vst2: return "vst"
        case .vst3: return "vst3"
        case .au: return "component"
        case .aax: return "aaxplugin"
        case .clap: return "clap"
        }
    }

    /// Folders DAWs scan. The matching unused folder is "<dir> (Unused)".
    var activeDirs: [String] {
        if self == .aax { return ["/Library/Application Support/Avid/Audio/Plug-Ins"] }
        let folder: String
        switch self {
        case .vst2: folder = "VST"
        case .vst3: folder = "VST3"
        case .au: folder = "Components"
        default: folder = "CLAP"
        }
        return ["/Library", NSHomeDirectory() + "/Library"].map { "\($0)/Audio/Plug-Ins/\(folder)" }
    }
}

enum Presence { case active, unused, missing }

struct PluginBundle: Hashable {
    let path: String
    let format: PluginFormat
    let activeDir: String
    let relPath: String
    let isUnused: Bool
    let name: String
    let version: String
    let bundleID: String
    let arch: String
    let installed: Date?

    /// Where the bundle goes when toggled: same relative path on the other side.
    var destination: String {
        (isUnused ? activeDir : activeDir + " (Unused)") + "/" + relPath
    }
}

/// A table row: either a vendor group (children != nil) or one plugin across formats.
struct Node: Identifiable {
    let id: String
    let name: String
    var bundles: [PluginBundle] = []
    var children: [Node]? = nil
    var vendor: String = ""
    var groupName: String = ""

    var isVendor: Bool { children != nil }
    var title: String { isVendor ? "\(name)  (\(children?.count ?? 0))" : name }

    func presence(_ f: PluginFormat) -> Presence {
        let b = bundles.filter { $0.format == f }
        if b.isEmpty { return .missing }
        return b.contains { !$0.isUnused } ? .active : .unused
    }

    // Sort keys for the table headers: 2 = active, 1 = in Unused / mixed, 0 = missing.
    private func rank(_ f: PluginFormat) -> Int {
        switch presence(f) { case .active: return 2; case .unused: return 1; case .missing: return 0 }
    }
    var rankVST2: Int { rank(.vst2) }
    var rankVST3: Int { rank(.vst3) }
    var rankAU: Int { rank(.au) }
    var rankAAX: Int { rank(.aax) }
    var rankCLAP: Int { rank(.clap) }
    var usedRank: Int {
        let active = bundles.filter { !$0.isUnused }.count
        return active == bundles.count ? 2 : (active == 0 ? 0 : 1)
    }

    private var primary: PluginBundle? { bundles.first { !$0.isUnused } ?? bundles.first }
    var version: String { primary?.version ?? "" }
    var arch: String { primary?.arch ?? "" }
    var installed: String {
        guard let d = bundles.compactMap(\.installed).max() else { return "" }
        return d.formatted(.iso8601.year().month().day())
    }
    var formats: String {
        PluginFormat.allCases.filter { presence($0) != .missing }.map(\.rawValue).joined(separator: ", ")
    }
}
