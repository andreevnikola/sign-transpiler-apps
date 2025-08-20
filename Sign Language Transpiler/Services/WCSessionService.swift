import Foundation
import WatchConnectivity

struct RecordingConfigPayload: Codable {
    struct PayloadGesture: Codable {
        let id: String
        let name_bg: String
        let tech: Int
    }
    struct PayloadTechInfo: Codable {
        let name: String
        let icon: String
    }
    let mode: String                // "record"
    let signerId: String
    let signerName: String
    let sessionId: String
    let gestures: [PayloadGesture]
    let techLegend: [Int: PayloadTechInfo]   // now includes icon too
}
final class WCSessionService: NSObject, ObservableObject {
    static let shared = WCSessionService()

    // Published gesture states coming from the Watch: "toRecord", "recording", "recorded"
    @Published var gestureStates: [String: String] = [:]  // gestureId -> state

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func sendRecordingConfig(_ cfg: RecordingConfigPayload) {
        guard WCSession.isSupported() else { return }
        guard WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else {
            NSLog("%@", "Watch not paired or app not installed"); return
        }
        do {
            let data = try JSONEncoder().encode(cfg)
            let msg: [String: Any] = ["type": "recording-config", "payload": data]
            sendMessage(msg)
        } catch {
            NSLog("%@", "encode error: \(error)")
        }
    }

    func sendMessage(_ dict: [String: Any]) {
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(dict, replyHandler: nil) { error in
                NSLog("%@", "sendMessage error: \(error)")
            }
        } else {
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: dict, requiringSecureCoding: false)
                try session.updateApplicationContext(["queued": data])
            } catch {
                NSLog("%@", "context error: \(error)")
            }
        }
    }
}

extension WCSessionService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let e = error { NSLog("%@", "WC activate error: \(e)") }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    #endif

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // Expect messages like: {"type":"gesture-state","gestureId":"DA","state":"recording"}
        guard let type = message["type"] as? String else { return }
        if type == "gesture-state",
           let gid = message["gestureId"] as? String,
           let state = message["state"] as? String {
            DispatchQueue.main.async {
                self.gestureStates[gid] = state
            }
        }
    }
}
