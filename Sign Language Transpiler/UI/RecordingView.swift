import SwiftUI

enum GestureRecordState: String {
    case toRecord = "toRecord"
    case recording = "recording"
    case recorded  = "recorded"

    var iconName: String {
        switch self {
        case .toRecord:  return "clock"
        case .recording: return "record.circle"
        case .recorded:  return "checkmark.circle"
        }
    }
    var color: Color {
        switch self {
        case .toRecord:  return .gray
        case .recording: return .orange
        case .recorded:  return .green
        }
    }
    var borderStyle: some ShapeStyle { color }
}

struct RecordingSheetView: View {
    let signer: Signer
    let sessionId: String

    @EnvironmentObject var catalog: GestureCatalog
    @EnvironmentObject var wc: WCSessionService
    @Environment(\.dismiss) private var dismiss

    @State private var states: [String: GestureRecordState] = [:]
    @State private var showCloseConfirm = false
    @State private var localSessionId: String = ""
    @State private var infoAlert: (show: Bool, text: String) = (false, "")

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Header (unchanged layout)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Apple Watch Gesture Record")
                            .font(.title2).bold()
                        Spacer()
                        Image(systemName: "stop.fill")
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.red))
                            .accessibilityHidden(true)
                    }
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill.viewfinder").foregroundStyle(.blue)
                            Text("Signer: \(signer.name)")
                        }
                        Divider().frame(height: 14)
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus").foregroundStyle(.purple)
                            Text("Session: \(localSessionId)")
                        }
                        Spacer()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 14)
                .padding(.bottom, 10)

                // Title above legend
                HStack {
                    Text("Gestures Available For Recording")
                        .font(.subheadline).bold()
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 6)

                // Legend
                HStack(spacing: 20) {
                    legendLabel(.toRecord)
                    legendLabel(.recording)
                    legendLabel(.recorded)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)

                // List
                if catalog.gestures.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        Text("No gestures loaded.\nEnsure **Gestures.json** is in Copy Bundle Resources for iOS and Watch Extension.")
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    Spacer()
                } else {
                    List {
                        ForEach(catalog.gestures) { g in
                            let st = states[g.id] ?? .toRecord
                            ZStack(alignment: .topTrailing) {
                                // status icon
                                Image(systemName: st.iconName)
                                    .foregroundStyle(st.color)
                                    .padding(8)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(g.name_bg) • \(g.id)")
                                        .font(.headline)

                                    // Technical Requirements line (icon from JSON)
                                    HStack(spacing: 8) {
                                        Button {
                                            infoAlert.text = "The technical requirements for the use/recording of this gesture are:\n\n\(catalog.legendText(for: g.tech))"
                                            infoAlert.show = true
                                        } label: {
                                            Image(systemName: "info.circle")
                                        }
                                        .buttonStyle(.plain)

                                        Text("Technical Requirements:")
                                            .font(.subheadline)

                                        // Capsule with icon defined in JSON legend
                                        HStack(spacing: 4) {
                                            Image(systemName: catalog.iconName(for: g.tech))
                                                .foregroundStyle(.blue)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.blue.opacity(0.12)))

                                        Spacer()
                                    }
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(st.borderStyle, lineWidth: 1.2)
                                )
                            }
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCloseConfirm = true } label: {
                        Label("Close", systemImage: "xmark.circle")
                    }
                }
            }
            .confirmationDialog(
                "Exit recording?",
                isPresented: $showCloseConfirm,
                titleVisibility: .visible
            ) {
                Button("Exit and discard unsaved data", role: .destructive) {
                    sendStop(); dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to close this window? All recorded data for this session that hasn’t been exported may be lost.")
            }
            .alert("Technical Requirements", isPresented: $infoAlert.show) {
                Button("Understood", role: .cancel) { infoAlert.show = false }
            } message: {
                Text(infoAlert.text)
            }
            .onAppear {
                localSessionId = sessionId.isEmpty ? "S1" : sessionId
                if catalog.gestures.isEmpty { catalog.loadFromBundle() }
                for g in catalog.gestures { if states[g.id] == nil { states[g.id] = .toRecord } }
            }
            .onReceive(wc.$gestureStates) { incoming in
                for (gid, s) in incoming {
                    if let mapped = GestureRecordState(rawValue: s) {
                        states[gid] = mapped
                    }
                }
            }
        }
        .interactiveDismissDisabled(true)
    }

    private func legendLabel(_ s: GestureRecordState) -> some View {
        HStack(spacing: 6) {
            Image(systemName: s.iconName).foregroundStyle(s.color)
            Text(label(for: s)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(6)
        .background { RoundedRectangle(cornerRadius: 6).fill(Color(.systemGray6)) }
    }
    private func label(for s: GestureRecordState) -> String {
        switch s {
        case .toRecord:  return "To be recorded"
        case .recording: return "Recording"
        case .recorded:  return "Recorded"
        }
    }

    private func sendStop() {
        wc.sendMessage([
            "mode": "stop-recording",
            "signerId": signer.id,
            "sessionId": localSessionId
        ])
    }
}
