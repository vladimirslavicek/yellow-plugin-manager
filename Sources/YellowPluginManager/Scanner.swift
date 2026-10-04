import Foundation

enum Scanner {
    private static let bundleExts = Set(PluginFormat.allCases.map(\.ext) + ["bundle", "app", "framework"])
    private static let vendorAliases = ["uaudio": "Universal Audio"]

    static func scan() -> [PluginBundle] {
        let fm = FileManager.default
        var out: [PluginBundle] = []
        for format in PluginFormat.allCases {
            for dir in format.activeDirs {
                for unused in [false, true] {
                    let base = unused ? dir + " (Unused)" : dir
                    guard let e = fm.enumerator(at: URL(fileURLWithPath: base),
                                                includingPropertiesForKeys: nil,
                                                options: [.skipsHiddenFiles]) else { continue }
                    for case let url as URL in e {
                        let ext = url.pathExtension.lowercased()
                        guard bundleExts.contains(ext) else { continue }
                        e.skipDescendants()
                        guard ext == format.ext, url.path.hasPrefix(base + "/") else { continue }
                        out.append(read(url, format: format, activeDir: dir, base: base, unused: unused))
                    }
                }
            }
        }
        return out
    }

    private static func read(_ url: URL, format: PluginFormat, activeDir: String, base: String, unused: Bool) -> PluginBundle {
        let path = url.path
        let name = url.deletingPathExtension().lastPathComponent
        let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist")
        let exe = (info?["CFBundleExecutable"] as? String) ?? name
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return PluginBundle(
            path: path,
            format: format,
            activeDir: activeDir,
            relPath: String(path.dropFirst(base.count + 1)),
            isUnused: unused,
            name: name,
            version: (info?["CFBundleShortVersionString"] as? String) ?? (info?["CFBundleVersion"] as? String) ?? "",
            bundleID: (info?["CFBundleIdentifier"] as? String) ?? "",
            arch: archs(of: path + "/Contents/MacOS/" + exe),
            installed: attrs?[.creationDate] as? Date
        )
    }

    /// Reads the Mach-O header: "arm64", "x86_64", "universal" or "" when unknown.
    static func archs(of path: String) -> String {
        guard let h = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? h.close() }
        let d = [UInt8](h.readData(ofLength: 512))
        guard d.count >= 8 else { return "" }
        func be(_ o: Int) -> UInt32 {
            guard o + 4 <= d.count else { return 0 }
            return UInt32(d[o]) << 24 | UInt32(d[o + 1]) << 16 | UInt32(d[o + 2]) << 8 | UInt32(d[o + 3])
        }
        func cpu(_ c: UInt32) -> String? {
            c == 0x0100_000C ? "arm64" : (c == 0x0100_0007 ? "x86_64" : nil)
        }
        var found: [String] = []
        let magic = be(0)
        if magic == 0xCAFE_BABE {
            for i in 0..<Int(min(be(4), 8)) {
                if let s = cpu(be(8 + i * 20)) { found.append(s) }
            }
        } else if magic == 0xCFFA_EDFE {
            let c = UInt32(d[4]) | UInt32(d[5]) << 8 | UInt32(d[6]) << 16 | UInt32(d[7]) << 24
            if let s = cpu(c) { found.append(s) }
        }
        if found.contains("arm64") && found.contains("x86_64") { return "universal" }
        return found.first ?? ""
    }

    // MARK: Grouping

    private static func key(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Mono variants ("Name(m)") pair with their stereo plugin.
    private static func baseName(_ name: String) -> String {
        name.hasSuffix("(m)") ? String(name.dropLast(3)).trimmingCharacters(in: .whitespaces) : name
    }

    private static func vendor(of bundles: [PluginBundle]) -> String {
        for b in bundles {
            let parts = b.relPath.split(separator: "/")
            if parts.count > 1 { return String(parts[0]) }
        }
        for b in bundles {
            let parts = b.bundleID.split(separator: ".")
            if parts.count > 1 {
                let v = String(parts[1])
                return vendorAliases[v.lowercased()] ?? v.prefix(1).uppercased() + v.dropFirst()
            }
        }
        return "Unknown"
    }

    /// Vendor groups, each holding one row per plugin with all its formats.
    static func tree(_ bundles: [PluginBundle]) -> [Node] {
        let rows = Dictionary(grouping: bundles) { key(baseName($0.name)) }.map { k, list -> (String, Node) in
            let sorted = list.sorted { $0.name.count < $1.name.count }
            let node = Node(id: "p:" + k, name: baseName(sorted[0].name), bundles: sorted)
            return (vendor(of: sorted), node)
        }
        var display: [String: String] = [:]
        var grouped: [String: [Node]] = [:]
        for (v, node) in rows {
            let vk = key(v)
            // Prefer a folder-style name (with spaces/capitals) as the group title.
            if display[vk] == nil || v.contains(" ") { display[vk] = v }
            grouped[vk, default: []].append(node)
        }
        return grouped.map { vk, nodes in
            Node(id: "v:" + vk, name: display[vk] ?? vk,
                 children: nodes.map { n in var n = n; n.vendor = display[vk] ?? vk; return n })
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
