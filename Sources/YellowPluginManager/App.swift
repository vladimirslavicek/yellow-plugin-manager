import SwiftUI

@main
struct YellowPluginManagerApp: App {
    @StateObject private var s = AppState()

    init() {
        // Read-only checks without the window: --scan and --selftest.
        if CommandLine.arguments.contains("--scan") || CommandLine.arguments.contains("--selftest") {
            let s = AppState()
            s.load(Scanner.scan())
            print("\(s.rows.count) plugins in \(s.tree.count) vendors, \(s.staleCopies) stale copies ignored")
            print("not in a group: \(s.rows.filter { s.group(of: $0) == nil }.count)")
            for g in s.groups {
                let m = s.members(g)
                print("group \(g.name): \(m.count) members, on=\(s.isOn(g))")
                s.mark(m, used: !s.isOn(g))
                print("  staging the opposite state: \(s.desired.count) rows, \(s.pendingBundles.count) bundles")
                s.discard()
            }
            exit(0)
        }
        // Lets the plain SwiftPM executable behave like a regular windowed app.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Yellow Plugin Manager") {
            ContentView(s: s)
                .frame(minWidth: 1100, minHeight: 600)
        }
        .commands {
            // File: the window is single, so New makes a group.
            CommandGroup(replacing: .newItem) {
                Button("New Group…") { s.newGroup(from: []) }
                    .keyboardShortcut("n", modifiers: .command)
                Menu("Open Plugin Folder") { FolderItems(s: s) }
                Divider()
                Button("Export as Markdown…") { s.exportMarkdown() }
                    .keyboardShortcut("e", modifiers: .command)
            }
            // View: filters, expand / collapse (as in Finder and Xcode), rescan.
            CommandGroup(after: .sidebar) {
                ForEach(Array(ViewFilter.allCases.enumerated()), id: \.offset) { i, f in
                    Button("Show \(f.rawValue)") { s.sidebar = .view(f) }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
                Divider()
                Button("Expand All Vendors") { s.expandAll() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Button("Collapse All Vendors") { s.collapseAll() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Divider()
                Button("Rescan Plugin Folders") { s.rescan() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
            }
            CommandMenu("Plugins") {
                PluginActions(s: s, picked: s.selectedRows, shortcuts: true)
                Divider()
                Button("Apply Changes") { s.apply() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(s.desired.isEmpty)
                Button("Discard Changes") { s.discard() }
                    .disabled(s.desired.isEmpty)
            }
            CommandMenu("Groups") {
                ForEach(s.groups) { g in
                    Menu(g.name) {
                        Button(s.isOn(g) ? "Switch to Unused" : "Switch to Used") { s.setGroup(g.id, on: !s.isOn(g)) }
                        Button("Enforce Group State") { s.enforce(g.id) }.disabled(s.overridden(g) == 0)
                        Button("Show Members") { s.sidebar = .group(g.id) }
                        Divider()
                        Button("Edit Group…") { s.editing = g }
                        Button("Delete Group") { s.deleteGroup(g.id) }
                    }
                }
                Divider()
                Button("New Group from Selection…") { s.newGroup(from: s.selectedRows) }
                    .disabled(s.selectedRows.isEmpty)
            }
        }
    }
}

/// Finder shortcuts to every plugin folder and its Unused twin.
struct FolderItems: View {
    @ObservedObject var s: AppState

    var body: some View {
        ForEach(PluginFormat.allCases) { f in
            Button("\(f.rawValue)") { s.openFolder(f.activeDirs[0]) }
            Button("\(f.rawValue) (Unused)") { s.openFolder(f.activeDirs[0] + " (Unused)") }
        }
    }
}

/// Everything that can be done to a set of plugins. Shared by the menu bar and the context menu.
struct PluginActions: View {
    @ObservedObject var s: AppState
    let picked: [Node]
    let shortcuts: Bool

    var body: some View {
        Button("Mark Used") { s.mark(picked, used: true) }
            .keyboardShortcut(shortcuts ? KeyboardShortcut("u", modifiers: .command) : nil)
            .disabled(!s.canMark(picked, used: true))
        Button("Mark Unused") { s.mark(picked, used: false) }
            .keyboardShortcut(shortcuts ? KeyboardShortcut("u", modifiers: [.command, .shift]) : nil)
            .disabled(!s.canMark(picked, used: false))
        // Single formats: only formats where the choice would change something are listed.
        Menu("Mark Format Used") { formatItems(true) }.disabled(formats(true).isEmpty)
        Menu("Mark Format Unused") { formatItems(false) }.disabled(formats(false).isEmpty)
        Divider()
        Menu("Move to Group") {
            ForEach(s.groups) { g in Button(g.name) { s.move(picked, to: g.id) } }
            Divider()
            Button("No Group") { s.move(picked, to: nil) }
            Button("New Group from Selection…") { s.newGroup(from: picked) }
        }
        .disabled(picked.isEmpty)
        Divider()
        Button("Show in Finder") { s.reveal(picked) }.disabled(picked.isEmpty)
    }

    private func formats(_ used: Bool) -> [PluginFormat] {
        PluginFormat.allCases.filter { s.canMarkFormat(picked, $0, used: used) }
    }

    @ViewBuilder
    private func formatItems(_ used: Bool) -> some View {
        ForEach(formats(used)) { f in
            Button(f.rawValue) { s.markFormat(picked, f, used: used) }
        }
    }
}

/// Small capsule label. Tinted background with regular text keeps it readable in light and dark mode.
struct Tag: View {
    let text: String
    var tint: Color = .secondary
    var strong = false

    var body: some View {
        Text(text)
            .font(.caption.weight(strong ? .semibold : .regular))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(tint.opacity(strong ? 0.3 : 0.15), in: Capsule())
            .foregroundStyle(strong ? .primary : .secondary)
            .lineLimit(1)
    }
}

struct PresenceCell: View {
    @ObservedObject var s: AppState
    let node: Node
    let format: PluginFormat

    var body: some View {
        if node.isVendor {
            Text("")
        } else {
            let p = s.presence(node, self.format)
            Group {
                switch p.state {
                case .active: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .unused: Image(systemName: "circle").foregroundStyle(.orange)
                case .missing: Text("")
                }
            }
            .padding(2)
            // A yellow halo marks a staged change of this one format.
            .background(Color.yellow.opacity(p.staged ? 0.5 : 0), in: Circle())
            .help(describe(p))
            .accessibilityLabel(describe(p))
        }
    }

    private func describe(_ p: (state: Presence, staged: Bool)) -> String {
        switch p.state {
        case .active: return p.staged ? "Will be used (not applied yet)" : "Used"
        case .unused: return p.staged ? "Will move to Unused (not applied yet)" : "In Unused"
        case .missing: return "Not installed"
        }
    }
}

/// Read-only status. A yellow tag is a staged change that has not been applied.
struct StatusCell: View {
    @ObservedObject var s: AppState
    let node: Node

    var body: some View {
        if let kids = node.children {
            let pending = s.pendingCount(in: node)
            if pending > 0 {
                Tag(text: "\(pending) pending", tint: .yellow, strong: true)
            } else {
                let used = kids.filter { s.current($0) == true }.count
                Text("\(used) of \(kids.count)").foregroundStyle(.secondary).monospacedDigit()
            }
        } else if s.isPending(node) {
            let e = s.effective(node)
            Tag(text: e == true ? "→ Used" : (e == false ? "→ Unused" : "→ Mixed"), tint: .yellow, strong: true)
        } else {
            switch s.current(node) {
            case .some(true): Text("Used")
            case .some(false): Text("Unused").foregroundStyle(.secondary)
            case .none: Text("Mixed").foregroundStyle(.orange)
            }
        }
    }
}

struct NameCell: View {
    @ObservedObject var s: AppState
    let node: Node

    var body: some View {
        HStack(spacing: 8) {
            if node.isVendor {
                Text(node.name).fontWeight(.semibold)
                Text("\(node.children?.count ?? 0)").foregroundStyle(.secondary).monospacedDigit()
            } else {
                Text(node.name)
            }
        }
    }
}

struct GroupRow: View {
    @ObservedObject var s: AppState
    let group: PluginGroup

    var body: some View {
        let differing = s.overridden(group)
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name)
                Text("\(s.members(group).count) plugins").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if differing > 0 {
                Button { s.enforce(group.id) } label: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .buttonStyle(.borderless)
                .help("\(differing) plugin(s) differ from this group's state. Click to enforce the group.")
                .accessibilityLabel("Enforce group")
            }
            Toggle("Used", isOn: Binding(get: { s.isOn(group) }, set: { s.setGroup(group.id, on: $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("On = plugins used, off = moved to Unused")
        }
        .contextMenu {
            Button("Edit Group…") { s.editing = group }
            Button("Enforce Group State") { s.enforce(group.id) }.disabled(group.enabled == nil)
            Divider()
            Button("Delete Group", role: .destructive) { s.deleteGroup(group.id) }
        }
    }
}

struct GroupEditor: View {
    @ObservedObject var s: AppState
    @State var group: PluginGroup
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let isNew = !s.groups.contains { $0.id == group.id }
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "New Group" : "Edit Group").font(.headline)
            TextField("Group name", text: $group.name)
            Text("Rules: a plugin matching any rule joins the group, unless it is already in another one.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach($group.rules) { $rule in
                HStack {
                    Picker("Rule type", selection: $rule.kind) {
                        ForEach(GroupRule.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                    TextField("Text to match", text: $rule.text)
                    Button { group.rules.removeAll { $0.id == rule.id } } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove rule")
                }
            }
            Button("Add Rule") { group.rules.append(GroupRule(kind: .nameStarts, text: "")) }
            HStack {
                Text("\(group.manual.count) plugin(s) added by hand")
                    .foregroundStyle(.secondary)
                if !group.manual.isEmpty {
                    Button("Clear") { group.manual = [] }
                }
            }
            Divider()
            HStack {
                if !isNew {
                    Button("Delete Group", role: .destructive) { s.deleteGroup(group.id); dismiss() }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { s.saveGroup(group); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(group.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 540)
    }
}

struct ContentView: View {
    @ObservedObject var s: AppState

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
        } detail: {
            VStack(spacing: 0) {
                if let n = s.notice { noticeBar(n) }
                if !s.desired.isEmpty { pendingBar }
                actionBar
                Divider()
                table
                Divider()
                footer
            }
        }
        .searchable(text: $s.search, prompt: "Search plugins or vendors")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    FolderItems(s: s)
                } label: { Label("Open Folder", systemImage: "folder") }
                    .help("Open a plugin folder in Finder")
                Button { s.exportMarkdown() } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .help("Export the selection, or everything shown, as Markdown")
                Button { s.rescan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .help("Rescan plugin folders (discards staged changes)")
            }
        }
        .sheet(item: $s.editing) { g in GroupEditor(s: s, group: g) }
        .task { s.rescan() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $s.sidebar) {
            Section("View") {
                ForEach(ViewFilter.allCases) { f in
                    Label(f.rawValue, systemImage: f.icon)
                        .badge(f == .pending ? s.stagedRows : 0)
                        .tag(SidebarItem.view(f))
                }
            }
            Section("Formats") {
                ForEach(PluginFormat.allCases) { f in
                    Text(f.rawValue).badge(s.count(f)).tag(SidebarItem.format(f))
                }
            }
            Section("Groups") {
                ForEach(s.groups) { g in
                    GroupRow(s: s, group: g).tag(SidebarItem.group(g.id))
                }
                Button { s.newGroup(from: []) } label: { Label("New Group…", systemImage: "plus") }
                    .buttonStyle(.borderless)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Banners

    private func noticeBar(_ n: Notice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: n.isError ? "exclamationmark.octagon.fill" : "checkmark.circle.fill")
                .foregroundStyle(n.isError ? .red : .green)
            Text(n.text).textSelection(.enabled)
            Spacer()
            Button { s.notice = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background((n.isError ? Color.red : Color.green).opacity(0.16))
    }

    private var pendingBar: some View {
        let bundles = s.pendingBundles
        let toUnused = bundles.filter { !$0.isUnused }.count
        return HStack(spacing: 10) {
            Image(systemName: "clock.fill").foregroundStyle(.orange)
            Text("\(s.stagedRows) plugin(s) staged: \(toUnused) bundle(s) to Unused, \(bundles.count - toUnused) to Used. Nothing has moved yet.")
                .fontWeight(.medium)
            Spacer()
            Button("Discard") { s.discard() }
            Button("Apply Changes") { s.apply() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.22))
    }

    /// Actions always work on the current table selection.
    private var actionBar: some View {
        let picked = s.selectedRows
        return HStack(spacing: 10) {
            Text(picked.isEmpty ? "Select plugins or vendors to change them" : "\(picked.count) plugin(s) selected")
                .foregroundStyle(picked.isEmpty ? .secondary : .primary)
            Spacer()
            Button { s.mark(picked, used: true) } label: { Label("Mark Used", systemImage: "checkmark.circle") }
                .disabled(!s.canMark(picked, used: true))
            Button { s.mark(picked, used: false) } label: { Label("Mark Unused", systemImage: "circle") }
                .disabled(!s.canMark(picked, used: false))
            Menu {
                moveMenu(picked)
            } label: { Label("Move to Group", systemImage: "folder") }
                .fixedSize()
                .disabled(picked.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private func moveMenu(_ picked: [Node]) -> some View {
        ForEach(s.groups) { g in Button(g.name) { s.move(picked, to: g.id) } }
        Divider()
        Button("No Group") { s.move(picked, to: nil) }
        Button("New Group from Selection…") { s.newGroup(from: picked) }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if s.busy { ProgressView().controlSize(.small) }
            Text(status).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text("used") }
            HStack(spacing: 4) { Image(systemName: "circle").foregroundStyle(.orange); Text("in Unused") }
            Text("empty = not installed").foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var status: String {
        let n = s.visible.reduce(0) { $0 + ($1.children?.count ?? 0) }
        let stale = s.staleCopies > 0 ? " · \(s.staleCopies) stale copies in Unused ignored" : ""
        return "\(n) plugins · \(s.visible.count) vendors" + stale
    }

    // MARK: Table

    private func expansion(_ id: String) -> Binding<Bool> {
        Binding(
            // While searching, every vendor with a hit is shown open.
            get: { !s.search.isEmpty || s.expanded.contains(id) },
            set: { open in
                // Option-click a disclosure triangle to expand or collapse all, as in Finder.
                if NSEvent.modifierFlags.contains(.option) {
                    if open { s.expandAll() } else { s.collapseAll() }
                } else if open {
                    s.expanded.insert(id)
                } else {
                    s.expanded.remove(id)
                }
            }
        )
    }

    private var table: some View {
        Table(of: Node.self, selection: $s.selection, sortOrder: $s.sortOrder) {
            TableColumn("Plugin", value: \.name, comparator: .localizedStandard) { n in NameCell(s: s, node: n) }
            TableColumn("Group", value: \.groupName) { n in
                if !n.groupName.isEmpty { Tag(text: n.groupName, tint: .accentColor) }
            }.width(min: 70, ideal: 110)
            TableColumn("Status", value: \.usedRank) { n in StatusCell(s: s, node: n) }.width(90)
            Group {
                TableColumn("VST2", value: \.rankVST2) { n in PresenceCell(s: s, node: n, format: .vst2) }.width(44)
                TableColumn("VST3", value: \.rankVST3) { n in PresenceCell(s: s, node: n, format: .vst3) }.width(44)
                TableColumn("AU", value: \.rankAU) { n in PresenceCell(s: s, node: n, format: .au) }.width(44)
                TableColumn("AAX", value: \.rankAAX) { n in PresenceCell(s: s, node: n, format: .aax) }.width(44)
                TableColumn("CLAP", value: \.rankCLAP) { n in PresenceCell(s: s, node: n, format: .clap) }.width(44)
            }
            TableColumn("Version", value: \.version, comparator: .localizedStandard) { n in
                Text(n.version).monospacedDigit()
            }.width(90)
            TableColumn("Installed", value: \.installed) { n in
                Text(n.installed).monospacedDigit().foregroundStyle(.secondary)
            }.width(90)
            TableColumn("Arch", value: \.arch) { n in Text(n.arch).foregroundStyle(.secondary) }.width(80)
        } rows: {
            ForEach(s.visible) { vendor in
                DisclosureTableRow(vendor, isExpanded: expansion(vendor.id)) {
                    ForEach(vendor.children ?? []) { TableRow($0) }
                }
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            PluginActions(s: s, picked: s.rows(for: ids), shortcuts: false)
        }
    }
}
