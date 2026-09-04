import SwiftUI
import Foundation
import Combine

// MARK: - On-Device Prompt Tree Models

struct PromptTreeNode: Identifiable, Codable {
    let id: String
    let parentId: String?
    let name: String
    let nodeType: String // "agent", "tool", "llm", "policy"
    let inputs: String
    let outputs: String
    let latencyMs: Double
    let narration: String
    let status: String // "success", "warning", "error"
    let timestamp: Date
}

struct PromptTreeSession: Identifiable, Codable {
    let id: String // e.g. session_id
    let title: String
    let timestamp: Date
    let nodes: [PromptTreeNode]
}

// MARK: - On-Device Prompt Tree Tracer (iOS Swift)

final class PromptTreeTracer: ObservableObject {
    static let shared = PromptTreeTracer()
    
    @Published var sessions: [PromptTreeSession] = []
    @Published var activeSession: PromptTreeSession?
    
    init() {
        generateDemoSession()
    }
    
    func recordSession(title: String, nodes: [PromptTreeNode]) {
        let session = PromptTreeSession(
            id: "session_\(UUID().uuidString.prefix(8))",
            title: title,
            timestamp: Date(),
            nodes: nodes
        )
        DispatchQueue.main.async {
            self.sessions.insert(session, at: 0)
            self.activeSession = session
        }
    }
    
    private func generateDemoSession() {
        let demoNodes = [
            PromptTreeNode(
                id: "node_1",
                parentId: nil,
                name: "FFM_Risk_Planning_Agent",
                nodeType: "agent",
                inputs: "Route: KSFO → KSJC | Aircraft: GA (120 KTAS, 8.5 GPH)",
                outputs: "Route verified. Safety envelope active.",
                latencyMs: 145.0,
                narration: "Initializing Field Foundation Model flight risk evaluation for 2 waypoints.",
                status: "success",
                timestamp: Date()
            ),
            PromptTreeNode(
                id: "node_2",
                parentId: "node_1",
                name: "Tool: Route_Leg_Analysis",
                nodeType: "tool",
                inputs: "Leg 1: KSFO (37.62, -122.37) → KSJC (37.36, -121.92)",
                outputs: "Distance: 28.4 NM | Icing: 0.2 | Turb: 0.4 | Terrain: 0.1",
                latencyMs: 32.0,
                narration: "Evaluating environmental hazards along flight path segment 1.",
                status: "success",
                timestamp: Date()
            ),
            PromptTreeNode(
                id: "node_3",
                parentId: "node_1",
                name: "Policy: Fuel_Reserve_Check",
                nodeType: "policy",
                inputs: "Est. Fuel: 2.0 gal | Reserve policy: 45 min (6.4 gal)",
                outputs: "Total required fuel: 8.4 gal. Policy satisfied.",
                latencyMs: 18.0,
                narration: "Enforcing FAR 91.151 minimum VFR 45-minute fuel reserve requirement.",
                status: "success",
                timestamp: Date()
            ),
            PromptTreeNode(
                id: "node_4",
                parentId: "node_1",
                name: "LLM: Safety_Advisory_Generator",
                nodeType: "llm",
                inputs: "Leg risks + Reserve validation",
                outputs: "Moderate turbulence forecast along route. 45m reserve fuel enforced.",
                latencyMs: 85.0,
                narration: "Generating final pilot advisory message.",
                status: "warning",
                timestamp: Date()
            )
        ]
        
        let demoSession = PromptTreeSession(
            id: "session_demo",
            title: "FFM Risk Plan: KSFO → KSJC",
            timestamp: Date(),
            nodes: demoNodes
        )
        self.sessions = [demoSession]
        self.activeSession = demoSession
    }
}
