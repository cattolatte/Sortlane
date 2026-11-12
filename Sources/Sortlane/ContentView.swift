import SwiftUI
import AppKit
import SortlaneCore

extension Color {
    static let laneAccent = Color(red: 0.39, green: 0.36, blue: 0.86)
    static let laneMint = Color(red: 0.20, green: 0.63, blue: 0.49)
    static let laneAmber = Color(red: 0.77, green: 0.49, blue: 0.15)
    static let laneInk = Color(red: 0.085, green: 0.105, blue: 0.16)
    static let laneLine = Color.primary.opacity(0.07)
    static let laneSurface = Color(nsColor: .controlBackgroundColor)
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appearance") private var appearance = "system"
    @State private var editingRule: SortingRule?
    @State private var confirmingAuto = false
    @State private var showAutomation = false
    @State private var customFolder = ""
    private var canvas: Color { colorScheme == .dark ? Color(red: 0.105, green: 0.12, blue: 0.16) : Color(red: 0.965, green: 0.963, blue: 0.95) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                header
                Divider()
                switch model.screen {
                case .inbox: workspace
                case .rules: rules
                case .history: activity
                }
                statusBar
            }.background(canvas)
        }
        .tint(.laneAccent)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        .onChange(of: model.inspectedProposal?.relativeDestination) { _, destination in
            customFolder = destination ?? "Documents"
        }
        .alert("Needs your attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .alert("Enable automatic moves?", isPresented: $confirmingAuto) {
            Button("Enable automatic moves") { model.automaticRules = true; model.monitoring = true; model.updateMonitoring() }
            Button("Keep review mode", role: .cancel) {}
        } message: {
            Text("Enabled rules can move files from \(model.source?.lastPathComponent ?? "your inbox") to \(model.destination?.lastPathComponent ?? "your destination") while Sortlane is open. AI and manually assigned destinations always require review. Changes to folders or rules pause automation.")
        }
        .sheet(item: $editingRule) { rule in
            RuleEditor(rule: rule) { edited in
                if let index = model.config.rules.firstIndex(where: { $0.id == edited.id }) { model.config.rules[index] = edited }
                else { model.config.rules.insert(edited, at: 0) }
                model.rulesChanged()
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 22, weight: .medium)).foregroundStyle(.white).frame(width: 44, height: 44).background(Color.laneAccent, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("sortlane").font(.system(size: 23, weight: .semibold, design: .rounded)).tracking(-0.8).foregroundStyle(.white)
                    Text("A LITTLE MORE ORDER").font(.system(size: 7, weight: .medium)).tracking(1.3).foregroundStyle(.white.opacity(0.4))
                }
            }.padding(.top, 38).padding(.bottom, 38)
            Text("YOUR SPACE").font(.system(size: 9, weight: .semibold)).tracking(1.7).foregroundStyle(.white.opacity(0.35)).padding(.leading, 12).padding(.bottom, 13)
            ForEach(Screen.allCases) { screen in
                Button { model.screen = screen } label: {
                    HStack(spacing: 12) {
                        Image(systemName: screen.symbol).font(.system(size: 15)).frame(width: 20)
                        Text(screen == .inbox ? "Workspace" : screen == .rules ? "Rules library" : "Activity").font(.system(size: 13, weight: .medium))
                        Spacer()
                        if screen == .inbox && !model.proposals.isEmpty { Text("\(model.proposals.count)").font(.system(size: 10, weight: .bold)).padding(.horizontal, 7).padding(.vertical, 3).background(.white.opacity(0.13), in: Capsule()) }
                    }.foregroundStyle(model.screen == screen ? .white : .white.opacity(0.52))
                        .padding(.horizontal, 12).frame(height: 45)
                        .background(model.screen == screen ? Color.white.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .leading) { if model.screen == screen { Capsule().fill(Color(red: 0.65, green: 0.63, blue: 1)).frame(width: 3, height: 18).padding(.leading, -3) } }
                }.buttonStyle(.plain).padding(.bottom, 6)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sparkles").foregroundStyle(Color(red: 0.73, green: 0.71, blue: 1))
                    Text("Intelligence, on your Mac").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                }
                Text(model.aiReady ? "Private document sorting.\nNo uploads. No subscriptions." : "Rules are ready to use.\nApple Intelligence is unavailable.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineSpacing(4)
                HStack(spacing: 6) {
                    Circle().fill(model.aiReady ? Color.laneMint : .laneAmber).frame(width: 5, height: 5)
                    Text(model.aiReady ? "Available on this Mac" : "Rules-only mode").font(.system(size: 9)).foregroundStyle(.white.opacity(0.65))
                    Spacer()
                    Button { model.refreshAI() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 10)) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.5)).help(model.aiStatus)
                }
            }.padding(15).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
            HStack(spacing: 6) {
                Image(systemName: "lock.shield").font(.system(size: 10))
                Text("LOCAL BY DESIGN").font(.system(size: 8, weight: .semibold)).tracking(1.1)
                Spacer()
                Text("0.2").font(.system(size: 10, design: .monospaced))
            }.foregroundStyle(.white.opacity(0.3)).padding(.top, 22).padding(.bottom, 23)
        }.padding(.horizontal, 19).frame(width: 220).background(Color.laneInk)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.screen == .inbox ? "Your files, in order." : model.screen == .rules ? "A smarter sorting routine." : "Every move, accounted for.")
                    .font(.system(size: 22, weight: .semibold)).tracking(-0.6)
                Text(model.screen == .inbox ? "Preview the plan. Keep the control." : model.screen == .rules ? "Build once. Organize effortlessly." : "A local history with checked, reversible moves.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if model.isDemo { tag("SAMPLE", color: .laneAmber) }
            Menu {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
            } label: { Image(systemName: "circle.lefthalf.filled") }.menuStyle(.borderlessButton).frame(width: 26).help("Appearance")
            if model.screen == .inbox {
                Button { Task { await model.scan() } } label: { Label("Scan folder", systemImage: "arrow.triangle.2.circlepath").padding(.vertical, 4) }
                    .buttonStyle(.borderedProminent).disabled(!model.canScan).keyboardShortcut("r")
            } else if model.screen == .rules {
                Button { editingRule = SortingRule(name: "New rule", extensions: [], destination: "Documents") } label: { Label("New rule", systemImage: "plus").padding(.vertical, 4) }.buttonStyle(.borderedProminent).disabled(model.busy || model.config.rules.count >= 100)
            }
        }.padding(.horizontal, 26).frame(height: 89)
    }

    private var workspace: some View {
        VStack(spacing: 17) {
            HStack(spacing: 12) {
                folderCard(source: true)
                Image(systemName: "arrow.right").font(.system(size: 14, weight: .medium)).foregroundStyle(.tertiary)
                folderCard(source: false)
            }
            HStack(spacing: 12) {
                metric("In your inbox", value: "\(model.proposals.count)", detail: "files found", symbol: "tray", tint: .laneAccent)
                metric("Selected", value: "\(model.selectedCount)", detail: ByteCountFormatter.string(fromByteCount: model.selectedBytes, countStyle: .file), symbol: "checkmark.circle", tint: .laneMint)
                metric("Needs review", value: "\(model.reviewCount)", detail: "you're in control", symbol: "eye", tint: .laneAmber)
            }
            HStack(spacing: 0) {
                queue.frame(maxWidth: .infinity, maxHeight: .infinity)
                if let proposal = model.inspectedProposal {
                    Divider()
                    inspector(proposal).frame(width: 244)
                }
            }.background(Color.laneSurface, in: RoundedRectangle(cornerRadius: 14)).clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.laneLine))
            HStack(spacing: 10) {
                Button { showAutomation.toggle() } label: {
                    HStack(spacing: 7) {
                        Circle().fill(model.automaticRules ? Color.laneMint : model.monitoring ? .laneAccent : .secondary.opacity(0.4)).frame(width: 6, height: 6)
                        Text(model.automaticRules ? "Automatic sorting on" : model.monitoring ? "Watching for new files" : "Review mode").font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                    }
                }.buttonStyle(.plain).popover(isPresented: $showAutomation) { automation }
                Text("·").foregroundStyle(.tertiary)
                Text("\(model.skipped) skipped").font(.system(size: 10)).foregroundStyle(.secondary).help("Hidden, protected, temporary, cloud-only, and recently modified files are skipped.")
                Spacer()
                Toggle("Subfolders", isOn: $model.config.recursive).toggleStyle(.checkbox).font(.system(size: 11)).disabled(!model.canScan).onChange(of: model.config.recursive) { _, _ in model.rulesChanged() }
            }.padding(.horizontal, 3)
        }.padding(24)
    }

    private func folderCard(source: Bool) -> some View {
        let url = source ? model.source : model.destination
        return Button { model.chooseFolder(isSource: source) } label: {
            HStack(spacing: 12) {
                Image(systemName: source ? "tray.and.arrow.down" : "folder.badge.plus").font(.system(size: 20)).foregroundStyle(Color.laneAccent).frame(width: 41, height: 41).background(Color.laneAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) {
                    Text(source ? "SOURCE FOLDER" : "DESTINATION").font(.system(size: 8, weight: .bold)).tracking(1.3).foregroundStyle(.secondary)
                    Text(url?.lastPathComponent ?? (source ? "Choose your inbox" : "Choose a home for your files")).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(url.map(shortPath) ?? "Click to choose a folder").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
            }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(Color.laneSurface, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.laneLine))
        }.buttonStyle(.plain).disabled(model.busy).help(url?.path ?? "Select folder")
    }

    private func metric(_ label: String, value: String, detail: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(tint).frame(width: 33)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 15).padding(.vertical, 12).frame(maxWidth: .infinity).background(Color.laneSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
    }

    private var queue: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
                TextField("Search files or destinations", text: $model.search).textFieldStyle(.plain).font(.system(size: 12))
                if !model.search.isEmpty { Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain).help("Clear search") }
                Menu { Picker("Sort files", selection: $model.queueSort) { ForEach(QueueSort.allCases) { Text($0.rawValue).tag($0) } } } label: { Image(systemName: "arrow.up.arrow.down") }.menuStyle(.borderlessButton).frame(width: 25).help("Sort files")
                Button { Task { await model.refineWithAI() } } label: { Label("Refine", systemImage: "sparkles") }.controlSize(.small).disabled(model.busy || !model.aiReady || model.proposals.isEmpty).help("Read documents and scanned images with on-device AI. Suggestions require your selection.")
            }.padding(14)
            HStack(spacing: 4) {
                ForEach(QueueFilter.allCases) { filter in
                    Button { model.queueFilter = filter } label: {
                        Text(filter.rawValue).font(.system(size: 10, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 6).foregroundStyle(model.queueFilter == filter ? Color.laneAccent : .secondary)
                            .background(model.queueFilter == filter ? Color.laneAccent.opacity(0.1) : .clear, in: Capsule())
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).padding(.bottom, 10)
            Divider()
            if model.proposals.isEmpty {
                emptyQueue
            } else if model.visibleProposals.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
                    Text("No files match this view").font(.system(size: 13, weight: .medium))
                    Button("Clear filters") { model.search = ""; model.queueFilter = .all }.buttonStyle(.link)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Menu {
                        Button("Select visible files") { model.selectVisible(true) }
                        Button("Deselect visible files") { model.selectVisible(false) }
                    } label: { Image(systemName: "checkmark.square").font(.system(size: 11)) }.menuStyle(.borderlessButton).frame(width: 24).disabled(model.busy).help("Batch selection applies to the current view")
                    Text("NAME").frame(maxWidth: .infinity, alignment: .leading)
                    if model.inspectedID == nil { Text("DESTINATION").frame(width: 150, alignment: .leading) }
                    Text("SOURCE").frame(width: 63, alignment: .leading)
                }.font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 9).background(canvas.opacity(0.5))
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.visibleProposals) { proposal in
                            fileRow(proposal)
                            Divider().padding(.leading, 53)
                        }
                    }
                }
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(model.selectedCount) selected").font(.system(size: 11, weight: .semibold))
                    Text("\(model.visibleProposals.count) shown · \(model.proposals.count) total").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await model.applySelected() } } label: {
                    HStack { Text("Organize selected"); Image(systemName: "arrow.right") }.font(.system(size: 11, weight: .semibold)).padding(.vertical, 5)
                }.buttonStyle(.borderedProminent).disabled(model.busy || model.selectedCount == 0)
            }.padding(14)
        }.frame(minHeight: 290)
    }

    private var emptyQueue: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(Color.laneAccent.opacity(0.06)).frame(width: 82, height: 82).rotationEffect(.degrees(-8))
                Image(systemName: model.lastScan == nil ? "tray.and.arrow.down" : "checkmark.seal").font(.system(size: 34, weight: .light)).foregroundStyle(Color.laneAccent)
            }
            Text(model.lastScan == nil ? "Good order starts here." : "A little breathing room.").font(.system(size: 18, weight: .semibold)).tracking(-0.4)
            Text(model.source == nil ? "Choose your folders to preview a sorting plan.\nNothing moves until you decide." : model.lastScan == nil ? "Scan your folder to see where each file belongs." : "No eligible files right now. New downloads appear\nafter they finish writing.").font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
            if model.source == nil {
                Button("Explore sample files") { Task { do { try await model.createDemo() } catch { model.error = error.localizedDescription } } }.buttonStyle(.bordered).disabled(!model.initialized || model.busy)
            } else if model.lastScan == nil { Button("Scan folder") { Task { await model.scan() } }.buttonStyle(.bordered).disabled(!model.canScan) }
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fileRow(_ proposal: FileProposal) -> some View {
        let category = FileCategory.allCases.first { proposal.relativeDestination?.hasPrefix($0.rawValue) == true }
        let focused = model.inspectedID == proposal.id
        return HStack(spacing: 10) {
            Toggle("Select \(proposal.snapshot.url.lastPathComponent)", isOn: Binding(get: { proposal.isSelected }, set: { model.setSelected(proposal.id, $0) })).labelsHidden().toggleStyle(.checkbox).disabled(model.busy || proposal.issue != nil || proposal.relativeDestination == nil)
            Image(systemName: category?.symbol ?? "doc.questionmark").font(.system(size: 17)).foregroundStyle(proposal.issue == nil ? Color.laneAccent.opacity(0.85) : .laneAmber).frame(width: 31, height: 37).background(Color.laneAccent.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 4) {
                Text(proposal.snapshot.url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(proposal.issue ?? "\(ByteCountFormatter.string(fromByteCount: proposal.snapshot.size, countStyle: .file)) · \(proposal.snapshot.url.pathExtension.uppercased())").font(.system(size: 9)).foregroundStyle(proposal.issue == nil ? .secondary : Color.laneAmber).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if model.inspectedID == nil { Text(proposal.relativeDestination ?? "Choose a destination").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 150, alignment: .leading).lineLimit(1).truncationMode(.middle) }
            tag(proposal.issue != nil ? "Conflict" : proposal.origin == .appleAI ? "AI" : proposal.origin == .manual ? "You" : proposal.origin == .rule ? "Rule" : "Review", color: proposal.issue != nil || proposal.origin == .unmatched ? .laneAmber : proposal.origin == .rule ? .laneMint : .laneAccent).frame(width: 63, alignment: .leading)
        }.padding(.horizontal, 14).padding(.vertical, 11).contentShape(Rectangle()).background(focused ? Color.laneAccent.opacity(0.07) : .clear)
            .onTapGesture { customFolder = proposal.relativeDestination ?? "Documents"; model.inspect(proposal.id) }
            .accessibilityElement(children: .contain).accessibilityLabel(proposal.snapshot.url.lastPathComponent)
            .contextMenu {
                Button("Inspect file") { customFolder = proposal.relativeDestination ?? "Documents"; model.inspectedID = proposal.id }
                Button("Reveal in Finder") { model.reveal(proposal.snapshot.url) }
                Divider()
                ForEach(FileCategory.allCases) { category in
                    Button("Send to \(category.rawValue)…") { Task { await model.assignDestination(id: proposal.id, folder: category.rawValue) } }.disabled(model.busy)
                }
            }
    }

    private func inspector(_ proposal: FileProposal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("FILE DETAILS").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(.secondary); Spacer(); Button { model.inspectedID = nil } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).help("Close inspector") }.padding(17)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "doc.text").font(.system(size: 35, weight: .light)).foregroundStyle(Color.laneAccent).padding(.top, 4)
                    Text(proposal.snapshot.url.lastPathComponent).font(.system(size: 15, weight: .semibold)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    HStack { Text(ByteCountFormatter.string(fromByteCount: proposal.snapshot.size, countStyle: .file)); Spacer(); Text(proposal.snapshot.url.pathExtension.uppercased()) }.font(.system(size: 10)).foregroundStyle(.secondary)
                    Divider()
                    detail("WHY THIS DESTINATION", value: proposal.reason)
                    detail("MODIFIED", value: proposal.snapshot.modified.formatted(date: .abbreviated, time: .shortened))
                    detail("CURRENT LOCATION", value: shortPath(proposal.snapshot.url.deletingLastPathComponent()))
                    if let issue = proposal.issue { Label(issue, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(Color.laneAmber) }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DESTINATION FOLDER").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
                        TextField("Documents/Receipts", text: $customFolder).textFieldStyle(.roundedBorder).font(.system(size: 11))
                        HStack {
                            Menu("Categories") { ForEach(FileCategory.allCases) { category in Button(category.rawValue) { customFolder = category.rawValue } } }.controlSize(.small)
                            Spacer()
                            Button("Apply") { Task { await model.assignDestination(id: proposal.id, folder: customFolder) } }.controlSize(.small).disabled(model.busy)
                        }
                        Text("Relative to your output folder. Manual destinations always need your review.").font(.system(size: 9)).foregroundStyle(.secondary).lineSpacing(3)
                    }
                    Button { model.reveal(proposal.snapshot.url) } label: { Label("Reveal in Finder", systemImage: "arrow.up.forward.square") }.controlSize(.small)
                }.padding(17)
            }
            Spacer(minLength: 0)
        }.background(canvas.opacity(0.65))
    }
    private func detail(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(.secondary); Text(value).font(.system(size: 11)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
    }

    private var automation: some View {
        VStack(alignment: .leading, spacing: 17) {
            Label("Your sorting routine", systemImage: "slider.horizontal.3").font(.headline)
            Toggle("Watch for new files", isOn: $model.monitoring).onChange(of: model.monitoring) { _, _ in model.updateMonitoring() }
            Text("Refreshes the review queue while the app is open.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("Move rule matches automatically", isOn: Binding(get: { model.automaticRules }, set: { if $0 { showAutomation = false; confirmingAuto = true } else { model.automaticRules = false } }))
            Text("AI and manual suggestions stay in review. Folder or rule changes pause automatic moves.").font(.caption).foregroundStyle(.secondary)
        }.toggleStyle(.switch).controlSize(.small).padding(22).frame(width: 320).disabled(!model.canScan)
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("First match wins. All conditions in a rule must match.", systemImage: "list.number").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button { model.importRules() } label: { Label("Import", systemImage: "square.and.arrow.down") }.controlSize(.small)
                Button { model.exportRules() } label: { Label("Export", systemImage: "square.and.arrow.up") }.controlSize(.small)
            }.disabled(model.busy)
            ScrollView {
                LazyVStack(spacing: 11) {
                    ForEach(Array(model.config.rules.enumerated()), id: \.element.id) { index, rule in
                        HStack(alignment: .center, spacing: 13) {
                            Text(String(format: "%02d", index + 1)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                            Toggle(rule.name, isOn: Binding(get: { model.config.rules.first(where: { $0.id == rule.id })?.isEnabled ?? false }, set: { value in
                                if let i = model.config.rules.firstIndex(where: { $0.id == rule.id }) { model.config.rules[i].isEnabled = value; model.rulesChanged() }
                            })).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(rule.name).font(.system(size: 14, weight: .semibold))
                                Text(ruleSummary(rule)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Label(rule.destination, systemImage: "folder").font(.system(size: 11)).foregroundStyle(Color.laneAccent).frame(width: 165, alignment: .leading).lineLimit(2)
                            Button("Edit") { editingRule = rule }.controlSize(.small)
                            Menu {
                                Button("Move up") { model.config.rules.swapAt(index, index - 1); model.rulesChanged() }.disabled(index == 0)
                                Button("Move down") { model.config.rules.swapAt(index, index + 1); model.rulesChanged() }.disabled(index == model.config.rules.count - 1)
                                Button("Duplicate") { var copy = rule; copy.id = UUID(); copy.name = String(copy.name.prefix(115)) + " copy"; model.config.rules.insert(copy, at: index + 1); model.rulesChanged() }.disabled(model.config.rules.count >= 100)
                                Divider()
                                Button("Remove rule", role: .destructive) { model.config.rules.removeAll { $0.id == rule.id }; model.rulesChanged() }
                            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22)
                        }.padding(19).background(Color.laneSurface, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.laneLine)).opacity(rule.isEnabled ? 1 : 0.55)
                    }
                }.disabled(model.busy)
            }
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 21)).foregroundStyle(Color.laneAccent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Give your folders a sense of time.").font(.system(size: 12, weight: .medium))
                    Text("Use Documents/{year}/{month} to organize by a file's modification date.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(18).background(Color.laneAccent.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        }.padding(24)
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search your activity", text: $model.historySearch).textFieldStyle(.plain)
                Spacer()
                Text("\(model.history.count) operations").font(.caption).foregroundStyle(.secondary)
            }.padding(13).background(Color.laneSurface, in: RoundedRectangle(cornerRadius: 10))
            if model.history.isEmpty { ContentUnavailableView("Your history starts here", systemImage: "clock.arrow.circlepath", description: Text("Every organized file gets a local record. No files have been moved yet.")).frame(maxHeight: .infinity) }
            else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.history.filter { model.historySearch.isEmpty || $0.source.lastPathComponent.localizedCaseInsensitiveContains(model.historySearch) || $0.destination.path.localizedCaseInsensitiveContains(model.historySearch) }) { op in
                            HStack(spacing: 13) {
                                Image(systemName: op.status == .undone ? "arrow.uturn.backward" : op.status == .moved ? "checkmark" : "exclamationmark.triangle").font(.system(size: 14, weight: .semibold)).foregroundStyle(op.status == .moved || op.status == .undone ? Color.laneMint : .laneAmber).frame(width: 35, height: 35).background(Color.laneMint.opacity(0.07), in: Circle())
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack { Text(op.source.lastPathComponent).font(.system(size: 12, weight: .semibold)); tag(op.status.rawValue, color: op.status == .moved ? .laneMint : .secondary) }
                                    Text(shortPath(op.status == .undone ? op.source : op.destination)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    if let message = op.message { Text(message).font(.system(size: 10)).foregroundStyle(Color.laneAmber) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Text(op.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.system(size: 10)).foregroundStyle(.secondary)
                                Button { model.reveal(op.status == .undone ? op.source : op.destination) } label: { Image(systemName: "arrow.up.forward.square") }.buttonStyle(.plain).help("Reveal in Finder")
                                Button("Undo") { Task { await model.undo(op) } }.controlSize(.small).disabled(op.status != .moved || model.busy)
                            }.padding(17).background(Color.laneSurface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.laneLine))
                        }
                    }
                }
            }
        }.padding(24)
    }

    private var statusBar: some View {
        VStack(spacing: 0) {
            if model.busy, let progress = model.progress { ProgressView(value: progress).progressViewStyle(.linear).frame(height: 2) }
            else { Divider() }
            HStack(spacing: 7) {
                if model.busy { ProgressView().controlSize(.mini) }
                else { Circle().fill(Color.laneMint).frame(width: 5, height: 5) }
                Text(model.status).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if model.workCancellable { Button("Stop") { model.cancelWork() }.controlSize(.mini) }
                else { Label("On your Mac", systemImage: "internaldrive").font(.system(size: 9)).foregroundStyle(.tertiary) }
            }.padding(.horizontal, 24).frame(height: 34)
        }
    }
    private func tag(_ title: String, color: Color) -> some View {
        Text(title.uppercased()).font(.system(size: 8, weight: .semibold)).tracking(0.4).foregroundStyle(color).padding(.horizontal, 7).padding(.vertical, 4).background(color.opacity(0.1), in: Capsule())
    }
    private func shortPath(_ url: URL) -> String {
        if model.isDemo, let range = url.path.range(of: "/Sample files/") { return "Sample workspace / " + url.path[range.upperBound...] }
        return url.path.replacingOccurrences(of: FolderPolicy.userHome.path, with: "~")
    }
    private func ruleSummary(_ rule: SortingRule) -> String {
        var parts = [rule.extensions.isEmpty ? "Any file type" : rule.extensions.joined(separator: ", ")]
        if !rule.nameContains.isEmpty { parts.append("name contains “\(rule.nameContains)”") }
        if let pattern = rule.namePattern, !pattern.isEmpty { parts.append(pattern) }
        if let age = rule.minimumAgeDays { parts.append("older than \(age.formatted()) days") }
        if let age = rule.maximumAgeDays { parts.append("newer than \(age.formatted()) days") }
        if rule.minimumBytes != nil || rule.maximumBytes != nil { parts.append("size filter") }
        if let excluded = rule.excludedNameContains, !excluded.isEmpty { parts.append("excludes “\(excluded)”") }
        return parts.joined(separator: " · ")
    }
}
