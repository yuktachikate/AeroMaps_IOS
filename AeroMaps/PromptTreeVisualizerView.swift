import SwiftUI

// MARK: - In-App Prompt Tree Visualizer View (SwiftUI for iOS)

struct PromptTreeVisualizerView: View {
    @StateObject private var tracer = PromptTreeTracer.shared
    @State private var selectedNode: PromptTreeNode? = nil
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Session Selector
                if !tracer.sessions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(tracer.sessions) { session in
                                Button(action: {
                                    withAnimation { tracer.activeSession = session }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "tree.circle.fill")
                                            .foregroundColor(tracer.activeSession?.id == session.id ? .green : .gray)
                                        Text(session.title)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(tracer.activeSession?.id == session.id ? Color.green.opacity(0.2) : Color(.tertiarySystemBackground))
                                    .foregroundColor(tracer.activeSession?.id == session.id ? .green : .primary)
                                    .cornerRadius(20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(tracer.activeSession?.id == session.id ? Color.green : Color.clear, lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .background(Color(.secondarySystemBackground))
                }
                
                // Visual Node Graph Tree
                ScrollView {
                    VStack(spacing: 16) {
                        if let session = tracer.activeSession {
                            let rootNodes = session.nodes.filter { $0.parentId == nil }
                            
                            ForEach(rootNodes) { root in
                                NodeTreeCard(node: root, allNodes: session.nodes, onSelect: { selectedNode = $0 })
                            }
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "tree.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                Text("No AI Traces Captured Yet")
                                    .font(.headline)
                                Text("Tap 'FFM Plan' in the bottom sheet to record a live AI decision tree.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.top, 60)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("🌳 AI Decision Tree")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedNode) { node in
                NodeDetailInspectorView(node: node)
            }
        }
    }
}

// MARK: - Node Tree Card & Flow Rendering

struct NodeTreeCard: View {
    let node: PromptTreeNode
    let allNodes: [PromptTreeNode]
    let onSelect: (PromptTreeNode) -> Void
    
    var childNodes: [PromptTreeNode] {
        allNodes.filter { $0.parentId == node.id }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Node Item
            Button(action: { onSelect(node) }) {
                HStack(spacing: 12) {
                    // Type Icon
                    Image(systemName: iconForType(node.nodeType))
                        .font(.title2)
                        .foregroundColor(colorForType(node.nodeType))
                        .frame(width: 36, height: 36)
                        .background(colorForType(node.nodeType).opacity(0.2))
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(node.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(Int(node.latencyMs)) ms")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        
                        Text(node.narration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(colorForType(node.nodeType).opacity(0.4), lineWidth: 1)
                )
            }
            
            // Render Child Flow Nodes recursively
            if !childNodes.isEmpty {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.blue.opacity(0.4))
                        .frame(width: 2)
                        .padding(.leading, 24)
                    
                    VStack(spacing: 12) {
                        ForEach(childNodes) { child in
                            NodeTreeCard(node: child, allNodes: allNodes, onSelect: onSelect)
                        }
                    }
                    .padding(.leading, 12)
                }
            }
        }
    }
    
    private func iconForType(_ type: String) -> String {
        switch type.lowercased() {
        case "agent": return "cpu"
        case "tool": return "wrench.and.screwdriver.fill"
        case "llm": return "brain.head.profile"
        case "policy": return "shield.checkmark.fill"
        default: return "node"
        }
    }
    
    private func colorForType(_ type: String) -> Color {
        switch type.lowercased() {
        case "agent": return .purple
        case "tool": return .orange
        case "llm": return .blue
        case "policy": return .green
        default: return .cyan
        }
    }
}

// MARK: - Node Detail Inspector View

struct NodeDetailInspectorView: View {
    let node: PromptTreeNode
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header Card
                    VStack(alignment: .leading, spacing: 8) {
                        Text(node.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Type: \(node.nodeType.capitalized) • Latency: \(Int(node.latencyMs)) ms")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    
                    // Narration Section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Agent Narration")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        Text(node.narration)
                            .font(.subheadline)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Inputs Section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Inputs")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        Text(node.inputs)
                            .font(.system(.footnote, design: .monospaced))
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    
                    // Outputs Section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Outputs")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        Text(node.outputs)
                            .font(.system(.footnote, design: .monospaced))
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Node Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
