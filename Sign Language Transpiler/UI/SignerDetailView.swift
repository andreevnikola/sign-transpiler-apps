import SwiftUI

// MARK: - Deletion model

enum PendingDeletion: Identifiable {
    case session(String)
    case gestureAll(String)
    case gestureInSession(gesture: String, session: String)

    var id: String {
        switch self {
        case .session(let s): return "session:\(s)"
        case .gestureAll(let g): return "gestureAll:\(g)"
        case .gestureInSession(let g, let s): return "gestureIn:\(g):\(s)"
        }
    }

    var title: String {
        switch self {
        case .session(let s): return "Delete session \(s)?"
        case .gestureAll(let g): return "Delete gesture \(g) (all sessions)?"
        case .gestureInSession(let g, let s): return "Delete gesture \(g) in session \(s)?"
        }
    }

    var message: String {
        switch self {
        case .session: return "This will permanently remove all CSVs in this session."
        case .gestureAll: return "This will permanently remove all CSVs for this gesture across all sessions."
        case .gestureInSession: return "This will permanently remove all CSVs for this gesture in the selected session."
        }
    }
}

// MARK: - Main view

struct SignerDetailView: View {
    @ObservedObject var storage: StorageService
    let signer: Signer

    @EnvironmentObject var catalog: GestureCatalog
    @EnvironmentObject var wc: WCSessionService

    @State private var sessions: [String] = []
    @State private var selectedSession: String? = nil
    @State private var groups: [GestureGroup] = []
    @State private var showingFilesFor: GestureGroup?

    @State private var pendingDeletion: PendingDeletion? = nil
    @State private var showDeleteAlert: Bool = false

    // Recording sheet
    @State private var showRecordingSheet = false
    @State private var recordingSessionId: String = ""

    var body: some View {
        List {
            // Session picker / delete row as a small subview (prevents type-check blowup)
            SessionPickerRow(
                sessions: sessions,
                selectedSession: $selectedSession,
                onDeleteSelectedSession: { sessionName in
                    pendingDeletion = .session(sessionName)
                    showDeleteAlert = true
                }
            )

            // Start recording
            Section {
                Button {
                    startRecording()
                } label: {
                    Label("Record Gestures", systemImage: "dot.radiowaves.left.and.right")
                        .font(.headline)
                }
            } footer: {
                Text("Starts a new recording session and notifies the paired Apple Watch.")
            }

            // Gestures list grouped
            gesturesListSection
        }
        .navigationTitle(signer.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { refreshAll() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .onAppear(perform: refreshAll)
        .sheet(isPresented: $showRecordingSheet) {
            RecordingSheetView(signer: signer, sessionId: recordingSessionId)
                .environmentObject(catalog)
                .environmentObject(wc)
                .presentationDetents([.large])
                .interactiveDismissDisabled(true)
        }
        .sheet(item: $showingFilesFor) { group in
            GestureFilesSheet(group: group)
        }
        .alert(pendingDeletion?.title ?? "Confirm Delete",
               isPresented: $showDeleteAlert,
               presenting: pendingDeletion) { item in
            Button("Delete", role: .destructive) { performDeletion(item) }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { item in
            Text(item.message)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var gesturesListSection: some View {
        if groups.isEmpty {
            Section {
                Text("No gesture CSVs for the selected session")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            }
        } else {
            ForEach(groups) { group in
                GestureRow(
                    group: group,
                    selectedSession: selectedSession,
                    onOpen: { showingFilesFor = group },
                    onDeleteInSession: { gestureId, sessionName in
                        pendingDeletion = .gestureInSession(gesture: gestureId, session: sessionName)
                        showDeleteAlert = true
                    },
                    onDeleteAll: { gestureId in
                        pendingDeletion = .gestureAll(gestureId)
                        showDeleteAlert = true
                    }
                )
            }
        }
    }

    // MARK: - Actions

    private func refreshAll() {
        sessions = storage.listSessions(for: signer)
        if let s = selectedSession, !sessions.contains(s) { selectedSession = nil }
        refresh()
    }

    private func refresh() {
        groups = storage.listGestureGroups(for: signer, session: selectedSession)
    }

    private func startRecording() {
        // Auto-increment short session id per signer
        recordingSessionId = makeAutoSessionId(for: signer.id)
        showRecordingSheet = true

        // Send config to watch
        let payload = RecordingConfigPayload(
            mode: "record",
            signerId: signer.id,
            signerName: signer.name,
            sessionId: recordingSessionId,
            gestures: catalog.gestures.map { .init(id: $0.id, name_bg: $0.name_bg, tech: $0.tech) },
            techLegend: catalog.techLegend.reduce(into: [Int: RecordingConfigPayload.PayloadTechInfo]()) { acc, kv in
                acc[kv.key] = .init(name: kv.value.name, icon: kv.value.icon)
            }
        )
        wc.sendRecordingConfig(payload)
    }

    private func performDeletion(_ item: PendingDeletion) {
        switch item {
        case .session(let s):
            do { try storage.deleteSession(signer, session: s) } catch { print("Failed to delete session \(s): \(error)") }
            selectedSession = nil
            pendingDeletion = nil
            refreshAll()

        case .gestureAll(let g):
            do { try storage.deleteGestureAllSessions(signer, gestureId: g) } catch { print("Failed to delete gesture \(g): \(error)") }
            pendingDeletion = nil
            refreshAll()

        case .gestureInSession(let g, let s):
            do { try storage.deleteGestureInSession(signer, gestureId: g, session: s) } catch { print("Failed to delete gesture \(g) in session \(s): \(error)") }
            pendingDeletion = nil
            refreshAll()
        }
    }

    /// Per-signer autoincrement session id stored in UserDefaults.
    private func makeAutoSessionId(for signerId: String) -> String {
        let key = "nextSessionId_\(signerId)"
        let current = max(1, UserDefaults.standard.integer(forKey: key))
        UserDefaults.standard.set(current + 1, forKey: key)
        return "S\(current)"
    }
}

// MARK: - Subviews

/// Small subview to avoid a huge nested expression in the main body.
private struct SessionPickerRow: View {
    let sessions: [String]
    @Binding var selectedSession: String?
    var onDeleteSelectedSession: (String) -> Void

    var body: some View {
        Section {
            HStack {
                Text("Session")
                Spacer()
                sessionMenu
                if let s = selectedSession {
                    Button {
                        onDeleteSelectedSession(s)
                    } label: {
                        Image(systemName: "trash").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete Session \(s)")
                }
            }
        }
    }

    private var sessionMenu: some View {
        Menu {
            Button("All Sessions") { selectedSession = nil }
            if !sessions.isEmpty {
                Divider()
            }
            ForEach(sessions, id: \.self) { s in
                Button(s) { selectedSession = s }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(selectedSession ?? "All Sessions")
            }
        }
    }
}

/// Row for a single gesture group with context actions, split out to simplify type-checking.
private struct GestureRow: View {
    let group: GestureGroup
    let selectedSession: String?
    var onOpen: () -> Void
    var onDeleteInSession: (_ gestureId: String, _ sessionName: String) -> Void
    var onDeleteAll: (_ gestureId: String) -> Void

    var body: some View {
        HStack {
            Button(action: onOpen) {
                HStack {
                    Image(systemName: "hand.draw.fill").foregroundStyle(.teal)
                    Text(group.id).font(.headline)
                    Spacer()
                    Text("\(group.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu {
            if let s = selectedSession {
                Button(role: .destructive) {
                    onDeleteInSession(group.id, s)
                } label: {
                    Label("Delete '\(group.id)' in session \(s)", systemImage: "trash")
                }
            }
            Button(role: .destructive) {
                onDeleteAll(group.id)
            } label: {
                Label("Delete '\(group.id)' (all sessions)", systemImage: "trash.slash")
            }
        }
        .swipeActions {
            if let s = selectedSession {
                Button(role: .destructive) {
                    onDeleteInSession(group.id, s)
                } label: {
                    Label("Delete (session \(s))", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    onDeleteAll(group.id)
                } label: {
                    Label("Delete (all sessions)", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Files sheet

struct GestureFilesSheet: View, Identifiable {
    let id = UUID()
    let group: GestureGroup

    var body: some View {
        NavigationStack {
            List(group.csvFiles, id: \.self) { url in
                VStack(alignment: .leading, spacing: 4) {
                    Text(url.lastPathComponent).font(.subheadline)
                    Text(url.deletingLastPathComponent().path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .navigationTitle(group.id)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
}
