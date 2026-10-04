import SwiftUI
import UniformTypeIdentifiers

enum ViewFilter: String, CaseIterable, Identifiable {
    case all = "All", active = "Used", unused = "Unused", ungrouped = "Not in a Group", pending = "Pending"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .active: return "checkmark.circle"
        case .unused: return "circle"
        case .ungrouped: return "tray"
        case .pending: return "clock"
        }
    }
}

enum SidebarItem: Hashable {
    case view(ViewFilter)
    case format(PluginFormat)
    case group(UUID)
}

/// Result line shown in the banner above the table.
struct Notice: Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
}

@MainActor
final class AppState: ObservableObject {
    @Published var tree: [Node] = []
    @Published var selection = Set<String>()
    @Published var expanded = Set<String>()
    @Published var search = ""
    @Published var sidebar: SidebarItem? = .view(.all)
    @Published var sortOrder = [KeyPathComparator(\Node.name, comparator: .localizedStandard)]
    @Published var busy = false
    /// Staged, not yet applied: bundle path → should that bundle be used (active).
    @Published var desired: [String: Bool] = [:]
    @Published var groups: [PluginGroup] = GroupStore.load()
    /// Plugin row id → the one group it belongs to.
    @Published private(set) var membership: [String: UUID] = [:]
    @Published var editing: PluginGroup?
    @Published var notice: Notice?
    /// Older copies left in Unused while the same plugin is also active. They are ignored
    /// (not shown, never moved back over the active copy) and replaced on the next move to Unused.
    @Published var staleCopies = 0

    private(set) var all: [PluginBundle] = []

    var rows: [Node] { tree.flatMap { $0.children ?? [] } }

    func load(_ found: [PluginBundle]) {
        let activeKeys = Set(found.filter { !$0.isUnused }.map { $0.format.rawValue + "|" + $0.name })
        let kept = found.filter { !$0.isUnused || !activeKeys.contains($0.format.rawValue + "|" + $0.name) }
        staleCopies = found.count - kept.count
        all = kept
        tree = Scanner.tree(kept)
        selection = []
        desired = [:]
        rebuildMembership()
    }

    func rescan() {
        busy = true
        Task {
            let found = await Task.detached { Scanner.scan() }.value
            load(found)
            busy = false
        }
    }

    func show(_ text: String, error: Bool = false) {
        let n = Notice(text: text, isError: error)
        notice = n
        guard !error else { return }
        Task {
            try? await Task.sleep(for: .seconds(8))
            if notice?.id == n.id { notice = nil }
        }
    }

    // MARK: State of a row

    /// true = all formats used, false = all in Unused, nil = mixed.
    func current(_ n: Node) -> Bool? {
        switch n.usedRank {
        case 2: return true
        case 0: return false
        default: return nil
        }
    }

    /// What the row will be once staged changes are applied.
    func effective(_ n: Node) -> Bool? {
        let used = n.bundles.filter { target($0) }.count
        if used == n.bundles.count { return true }
        return used == 0 ? false : nil
    }

    private func target(_ b: PluginBundle) -> Bool { desired[b.path] ?? !b.isUnused }

    private func stage(_ b: PluginBundle, _ used: Bool) {
        if b.isUnused != used { desired[b.path] = nil } else { desired[b.path] = used }
    }

    func isPending(_ n: Node) -> Bool { n.bundles.contains { desired[$0.path] != nil } }

    var stagedRows: Int { rows.filter { isPending($0) }.count }

    func set(_ n: Node, _ used: Bool) { n.bundles.forEach { stage($0, used) } }

    // One format of a plugin, e.g. only the AAX bundle of a WaveShell.

    /// State of one format once staged changes are applied, and whether a change is staged.
    func presence(_ n: Node, _ f: PluginFormat) -> (state: Presence, staged: Bool) {
        let b = n.bundles.filter { $0.format == f }
        if b.isEmpty { return (.missing, false) }
        return (b.contains { target($0) } ? .active : .unused, b.contains { desired[$0.path] != nil })
    }

    func markFormat(_ list: [Node], _ f: PluginFormat, used: Bool) {
        for n in list { for b in n.bundles where b.format == f { stage(b, used) } }
    }

    func canMarkFormat(_ list: [Node], _ f: PluginFormat, used: Bool) -> Bool {
        list.contains { n in n.bundles.contains { $0.format == f && target($0) != used } }
    }

    func mark(_ list: [Node], used: Bool) { list.forEach { set($0, used) } }

    /// Whether marking would change anything: false when every row already is in that state.
    func canMark(_ list: [Node], used: Bool) -> Bool { list.contains { effective($0) != used } }

    func pendingCount(in v: Node) -> Int { (v.children ?? []).filter { isPending($0) }.count }

    // MARK: Groups (a plugin is in at most one)

    /// A hand-made assignment wins over rules; among rules the first group in the list wins.
    private func owner(of n: Node) -> UUID? {
        if let g = groups.first(where: { $0.manual.contains(n.id) }) { return g.id }
        return groups.first { g in
            !(g.excluded ?? []).contains(n.id) && g.rules.contains { $0.matches(n) }
        }?.id
    }

    private func rebuildMembership() {
        var map: [String: UUID] = [:]
        for n in rows { if let id = owner(of: n) { map[n.id] = id } }
        membership = map
    }

    private func groupsChanged() {
        rebuildMembership()
        GroupStore.save(groups)
    }

    func group(of n: Node) -> PluginGroup? {
        guard let id = membership[n.id] else { return nil }
        return groups.first { $0.id == id }
    }

    func members(_ g: PluginGroup) -> [Node] { rows.filter { membership[$0.id] == g.id } }

    func isOn(_ g: PluginGroup) -> Bool {
        if let e = g.enabled { return e }
        let m = members(g)
        return !m.isEmpty && m.allSatisfy { effective($0) == true }
    }

    /// Number of members whose state differs from what the group was switched to.
    func overridden(_ g: PluginGroup) -> Int {
        guard let e = g.enabled else { return 0 }
        return members(g).filter { effective($0) != e }.count
    }

    func setGroup(_ id: UUID, on: Bool) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[i].enabled = on
        mark(members(groups[i]), used: on)
        GroupStore.save(groups)
    }

    /// Re-applies the group's state to members that were changed individually.
    func enforce(_ id: UUID) {
        guard let g = groups.first(where: { $0.id == id }), let e = g.enabled else { return }
        mark(members(g), used: e)
    }

    /// Moves plugins into a group, or out of every group when `id` is nil.
    func move(_ list: [Node], to id: UUID?) {
        let ids = Set(list.map(\.id))
        for i in groups.indices { groups[i].manual.removeAll { ids.contains($0) } }
        if let id, let i = groups.firstIndex(where: { $0.id == id }) {
            groups[i].manual.append(contentsOf: list.map(\.id))
            groups[i].excluded?.removeAll { ids.contains($0) }
        } else {
            // Leaving all groups: also opt out of every rule that would still claim the plugin.
            for n in list {
                for i in groups.indices where groups[i].rules.contains(where: { $0.matches(n) }) {
                    var ex = groups[i].excluded ?? []
                    if !ex.contains(n.id) { ex.append(n.id) }
                    groups[i].excluded = ex
                }
            }
        }
        groupsChanged()
    }

    func saveGroup(_ g: PluginGroup) {
        let ids = Set(g.manual)
        for i in groups.indices where groups[i].id != g.id { groups[i].manual.removeAll { ids.contains($0) } }
        if let i = groups.firstIndex(where: { $0.id == g.id }) { groups[i] = g } else { groups.append(g) }
        groupsChanged()
    }

    func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        if sidebar == .group(id) { sidebar = .view(.all) }
        groupsChanged()
    }

    func newGroup(from list: [Node]) {
        editing = PluginGroup(name: "New Group", manual: list.map(\.id))
    }

    // MARK: Filtering and sorting

    func count(_ f: PluginFormat) -> Int { rows.filter { $0.presence(f) != .missing }.count }

    var visible: [Node] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let vendors: [Node] = tree.compactMap { v in
            let vendorHit = v.name.lowercased().contains(q)
            let kids = (v.children ?? []).filter { n in
                switch sidebar {
                case .view(.active): if !n.bundles.contains(where: { !$0.isUnused }) { return false }
                case .view(.unused): if !n.bundles.contains(where: { $0.isUnused }) { return false }
                case .view(.ungrouped): if membership[n.id] != nil { return false }
                case .view(.pending): if !isPending(n) { return false }
                case .format(let f): if n.presence(f) == .missing { return false }
                case .group(let id): if membership[n.id] != id { return false }
                default: break
                }
                return q.isEmpty || vendorHit || n.name.lowercased().contains(q)
            }
            let named = kids.map { n -> Node in
                var n = n
                n.groupName = group(of: n)?.name ?? ""
                return n
            }
            return named.isEmpty ? nil : Node(id: v.id, name: v.name, children: named.sorted(using: sortOrder))
        }
        // Plugin column: vendors A–Z or Z–A. Any other column: plugins are sorted inside each
        // vendor and vendors follow their first plugin, so the best match of the sort is on top.
        let byNameColumn = sortOrder.first?.keyPath == \Node.name
        let reversed = sortOrder.first?.order == .reverse
        return vendors.sorted { a, b in
            if !byNameColumn, let x = a.children?.first, let y = b.children?.first {
                for c in sortOrder where c.keyPath != \Node.name {
                    let r = c.compare(x, y)
                    if r != .orderedSame { return r == .orderedAscending }
                }
            }
            let r = a.name.localizedStandardCompare(b.name)
            return byNameColumn && reversed ? r == .orderedDescending : r == .orderedAscending
        }
    }

    /// Plugin rows for a set of table ids; a vendor id stands for all its visible plugins.
    func rows(for ids: Set<String>) -> [Node] {
        visible.flatMap { v -> [Node] in
            let kids = v.children ?? []
            return ids.contains(v.id) ? kids : kids.filter { ids.contains($0.id) }
        }
    }

    var selectedRows: [Node] { rows(for: selection) }

    func expandAll() { expanded = Set(tree.map(\.id)) }
    func collapseAll() { expanded = [] }

    // MARK: Applying staged changes

    /// Bundles that have to move to reach the staged state.
    var pendingBundles: [PluginBundle] {
        all.filter { desired[$0.path] != nil }
    }

    func discard() { desired = [:] }

    /// Moves everything staged, right away. The result goes to the banner.
    func apply() {
        let bundles = pendingBundles
        guard !bundles.isEmpty else { desired = [:]; return }
        let r = Mover.perform(bundles)
        var text = "\(r.moved) bundle(s) moved"
        if r.replaced > 0 { text += ", \(r.replaced) older copy(ies) sent to Trash" }
        if !r.failed.isEmpty {
            text += ". \(r.failed.count) failed: " + r.failed.prefix(6).joined(separator: ", ")
            if r.failed.count > 6 { text += " …" }
        }
        show(text + ".", error: !r.failed.isEmpty)
        rescan()
    }

    // MARK: Finder helpers

    func openFolder(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            show("Folder does not exist yet: \(path)", error: true)
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func reveal(_ list: [Node]) {
        let urls = list.flatMap(\.bundles).prefix(40).map { URL(fileURLWithPath: $0.path) }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(Array(urls)) }
    }

    // MARK: Export

    /// Markdown list of the selection (or of everything visible when nothing is selected).
    func exportMarkdown() {
        let picked = Set(selectedRows.map(\.id))
        var lines = [
            "# Installed audio plugins",
            "",
            "Exported \(Date().formatted(.iso8601.year().month().day())) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "",
            "Task: for each plugin, find the latest released version from the vendor and list only the plugins that are outdated, with the latest version and a download link.",
            "",
            "| Vendor | Plugin | Version | Formats | Arch | Installed |",
            "| --- | --- | --- | --- | --- | --- |",
        ]
        var count = 0
        for v in visible {
            for n in v.children ?? [] where picked.isEmpty || picked.contains(n.id) {
                lines.append("| \(v.name) | \(n.name) | \(n.version) | \(n.formats) | \(n.arch) | \(n.installed) |")
                count += 1
            }
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "plugins.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            show("Exported \(count) plugin(s) to \(url.lastPathComponent).")
        } catch {
            show("Export failed: \(error.localizedDescription)", error: true)
        }
    }
}
