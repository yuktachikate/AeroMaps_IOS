import { useState, useCallback, useEffect, useRef } from 'react';
import ReactFlow, {
  Controls,
  Background,
  useNodesState,
  useEdgesState,
  type Edge,
  type Node,
  MiniMap,
  ReactFlowProvider,
  MarkerType,
} from 'reactflow';
import 'reactflow/dist/style.css';
import { getLayoutedElements } from './layout';
import CustomNode from './nodes/CustomNode';
import { fetchSessions, fetchSessionTree, updateNodeAnnotation, runDemo, importTraces } from './api';
import type { TraceNode } from './types';
import { Monitor, RefreshCw, GitBranch, Layers, X, AlertCircle, Play, Loader2, Upload, Volume2, VolumeX } from 'lucide-react';

const nodeTypes = {
  custom: CustomNode,
};

function App() {
  const [sessions, setSessions] = useState<string[]>([]);
  const [selectedSession, setSelectedSession] = useState<string | null>(null);
  const [selectedNode, setSelectedNode] = useState<TraceNode | null>(null);
  const [isRunningDemo, setIsRunningDemo] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Voice State
  const [isVoiceEnabled, setIsVoiceEnabled] = useState(false);
  const spokeNodeIds = useRef<Set<string>>(new Set());

  const [nodes, setNodes, onNodesChange] = useNodesState([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState([]);

  const loadSessions = useCallback(async () => {
    const list = await fetchSessions();
    setSessions(list);
    if (!selectedSession && list.length > 0) {
      setSelectedSession(list[0]);
    }
  }, [selectedSession]);

  useEffect(() => {
    loadSessions();
  }, []);

  const triggerDemo = async () => {
    setIsRunningDemo(true);
    // Reset spoken nodes for new demo
    spokeNodeIds.current.clear();
    try {
      await runDemo();
      // Wait a bit for it to start
      setTimeout(() => {
        loadSessions();
        setIsRunningDemo(false);
      }, 3000);
    } catch (e) {
      console.error(e);
      setIsRunningDemo(false);
    }
  };

  const handleFileUpload = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = async (e) => {
      try {
        const json = JSON.parse(e.target?.result as string);
        if (Array.isArray(json)) {
          await importTraces(json);
          await loadSessions();
          // Select the imported session if available
          if (json.length > 0 && json[0].session_id) {
            setSelectedSession(json[0].session_id);
          }
          alert("Import successful!");
        } else {
          alert("Invalid file format: Expected an array of trace nodes.");
        }
      } catch (error) {
        console.error("Import failed:", error);
        alert("Failed to import file. Check console for details.");
      }
    };
    reader.readAsText(file);
    // Reset input
    event.target.value = '';
  };

  const speak = (text: string) => {
    if (!isVoiceEnabled || !window.speechSynthesis) return;
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.rate = 0.9;
    window.speechSynthesis.speak(utterance);
  };

  const loadTree = useCallback(async () => {
    if (!selectedSession) return;

    const traceNodes = await fetchSessionTree(selectedSession);

    // Check for new nodes to speak
    if (isVoiceEnabled) {
      traceNodes.forEach(node => {
        if (!spokeNodeIds.current.has(node.node_id)) {
          spokeNodeIds.current.add(node.node_id);
          // Speak narration if available, otherwise name
          const text = node.metadata?.narration || `Running ${node.name}`;
          speak(text);
        }
      });
    }

    // Transform to React Flow
    const newNodes: Node[] = traceNodes.map(t => ({
      id: t.node_id,
      type: 'custom',
      data: t,
      position: { x: 0, y: 0 }, // layout handles this
    }));

    const newEdges: Edge[] = traceNodes
      .filter(t => t.parent_id)
      .map(t => ({
        id: `${t.parent_id}-${t.node_id}`,
        source: t.parent_id!,
        target: t.node_id,
        type: 'smoothstep',
        animated: true,
        markerEnd: {
          type: MarkerType.ArrowClosed,
          color: '#cbd5e1',
        },
        style: { stroke: '#cbd5e1', strokeWidth: 2 },
      }));

    const { nodes: layoutedNodes, edges: layoutedEdges } = getLayoutedElements(
      newNodes,
      newEdges
    );

    setNodes(layoutedNodes);
    setEdges(layoutedEdges);
  }, [selectedSession, setNodes, setEdges, isVoiceEnabled]);

  useEffect(() => {
    loadTree();
    const treeInterval = setInterval(loadTree, 3000); // Faster polling for voice
    const sessionInterval = setInterval(loadSessions, 5000); // Auto-refresh sessions list
    return () => {
      clearInterval(treeInterval);
      clearInterval(sessionInterval);
    };
  }, [loadTree, loadSessions]);

  const onNodeClick = (_: any, node: Node) => {
    setSelectedNode(node.data);
  };

  const updateAnnotation = async (text: string, flag: boolean) => {
    if (!selectedNode) return;
    const updated = await updateNodeAnnotation(selectedNode.node_id, { annotations: text, flagged: flag });
    setSelectedNode(updated);
    loadTree();
  };

  return (
    <div className="flex h-screen w-screen bg-slate-50 text-slate-800 overflow-hidden font-sans">
      {/* Sidebar - Sessions */}
      <div className="w-72 bg-white border-r border-slate-200 flex flex-col z-20 shadow-xl">
        <div className="p-5 border-b border-slate-100 flex items-center justify-between">
          <h1 className="flex items-center gap-2.5 font-bold text-lg text-slate-800">
            <div className="w-8 h-8 bg-blue-500 rounded-lg flex items-center justify-center shadow-blue-200 shadow-md">
              <Monitor size={18} className="text-white" />
            </div>
            Prompt Tree
          </h1>
          <button
            onClick={() => setIsVoiceEnabled(!isVoiceEnabled)}
            className={`p-2 rounded-full transition-all ${isVoiceEnabled ? 'bg-blue-100 text-blue-600' : 'text-slate-400 hover:bg-slate-100'}`}
            title={isVoiceEnabled ? "Mute Agent Voice" : "Enable Agent Voice"}
          >
            {isVoiceEnabled ? <Volume2 size={18} /> : <VolumeX size={18} />}
          </button>
        </div>

        <div className="p-4 border-b border-slate-100 bg-slate-50/50 space-y-2">
          <button
            onClick={triggerDemo}
            disabled={isRunningDemo}
            className="w-full button-primary flex items-center justify-center gap-2 group disabled:opacity-70 disabled:cursor-not-allowed"
          >
            {isRunningDemo ? <Loader2 size={16} className="animate-spin" /> : <Play size={16} className="group-hover:fill-current" />}
            <span>{isRunningDemo ? 'Running...' : 'Run Live Demo'}</span>
          </button>

          <div className="relative">
            <input
              type="file"
              accept=".json"
              ref={fileInputRef}
              className="hidden"
              onChange={handleFileUpload}
            />
            <button
              onClick={() => fileInputRef.current?.click()}
              className="w-full button-secondary flex items-center justify-center gap-2 group"
            >
              <Upload size={16} className="text-slate-500 group-hover:text-blue-500" />
              <span>Import JSON</span>
            </button>
          </div>
        </div>

        <div className="flex-1 overflow-y-auto p-3 scrollbar-thin">
          <div className="flex items-center justify-between px-2 py-2 mb-2 text-xs text-slate-400 font-bold uppercase tracking-wider">
            <span>Recent Sessions</span>
            <button onClick={loadSessions} className="hover:text-blue-500 transition-colors p-1 rounded hover:bg-slate-100"><RefreshCw size={14} /></button>
          </div>

          <div className="space-y-1">
            {sessions.map(s => (
              <button
                key={s}
                onClick={() => setSelectedSession(s)}
                className={`w-full text-left px-3 py-3 rounded-lg text-sm truncate transition-all flex items-center gap-3 border
                            ${selectedSession === s
                    ? 'bg-blue-50 text-blue-700 border-blue-200 shadow-sm font-medium'
                    : 'bg-transparent border-transparent hover:bg-slate-50 text-slate-600 hover:text-slate-900'}
                        `}
              >
                <GitBranch size={16} className={selectedSession === s ? "text-blue-500" : "text-slate-400"} />
                <span className="truncate">{s}</span>
              </button>
            ))}
          </div>

          {sessions.length === 0 && (
            <div className="text-center p-8 text-slate-400 text-sm italic border-2 border-dashed border-slate-200 rounded-xl m-2 bg-slate-50">
              No sessions yet.<br />Click "Run Live Demo" above!
            </div>
          )}
        </div>
      </div>

      {/* Main Content - Graph */}
      <div className="flex-1 relative bg-slate-50/50">
        <ReactFlow
          nodes={nodes}
          edges={edges}
          onNodesChange={onNodesChange}
          onEdgesChange={onEdgesChange}
          onNodeClick={onNodeClick}
          nodeTypes={nodeTypes}
          fitView
          className="bg-slate-50/50"
          minZoom={0.1}
        >
          <Background color="#e2e8f0" gap={20} size={1} />
          <Controls className="bg-white border-slate-200 shadow-xl text-slate-600 rounded-lg overflow-hidden" />
          <MiniMap
            style={{ background: 'rgba(255,255,255,0.8)', border: '1px solid #e2e8f0' }}
            nodeColor={() => '#cbd5e1'}
            maskColor="rgba(241, 245, 249, 0.6)"
          />
        </ReactFlow>

        {/* Side Panel - Details */}
        <div className={`side-panel ${selectedNode ? 'open' : ''}`}>
          {selectedNode && (
            <div className="h-full flex flex-col">
              <div className="pb-4 mb-4 border-b border-slate-100 flex items-center justify-between">
                <h2 className="text-lg font-bold flex items-center gap-2 text-slate-800">
                  <Layers size={20} className="text-blue-500" />
                  Node Details
                </h2>
                <button onClick={() => setSelectedNode(null)} className="text-slate-400 hover:text-slate-600 transition-colors p-1 hover:bg-slate-100 rounded-full">
                  <X size={20} />
                </button>
              </div>

              <div className="flex-1 overflow-y-auto space-y-6 custom-scrollbar pr-2">
                {/* ID Badge */}
                <div className="text-[10px] font-mono text-slate-400 truncate bg-slate-50 p-1.5 rounded border border-slate-100 text-center select-all">
                  {selectedNode.node_id}
                </div>

                {/* Summary Grid */}
                <div className="grid grid-cols-2 gap-3">
                  <div className="bg-slate-50 p-3 rounded-lg border border-slate-100">
                    <label className="text-slate-400 text-[10px] uppercase font-bold tracking-wider block mb-1">Name</label>
                    <div className="font-semibold text-sm text-slate-700 truncate" title={selectedNode.name}>{selectedNode.name}</div>
                  </div>
                  <div className="bg-slate-50 p-3 rounded-lg border border-slate-100">
                    <label className="text-slate-400 text-[10px] uppercase font-bold tracking-wider block mb-1">Latency</label>
                    <div className="font-mono text-sm text-emerald-600 font-medium">{selectedNode.latency_ms?.toFixed(2)}ms</div>
                  </div>
                  <div className="bg-slate-50 p-3 rounded-lg border border-slate-100">
                    <label className="text-slate-400 text-[10px] uppercase font-bold tracking-wider block mb-1">Tokens</label>
                    <div className="font-mono text-sm text-purple-600 font-medium">{selectedNode.token_count || 0}</div>
                  </div>
                  <div className="bg-slate-50 p-3 rounded-lg border border-slate-100">
                    <label className="text-slate-400 text-[10px] uppercase font-bold tracking-wider block mb-1">Type</label>
                    <div className="font-mono text-sm text-blue-600 font-medium">{selectedNode.node_type}</div>
                  </div>
                </div>

                {/* Inputs */}
                <div>
                  <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Inputs</h3>
                  <div className="code-block group relative">
                    <pre className="text-xs font-mono text-slate-600 overflow-x-auto whitespace-pre-wrap leading-relaxed">
                      {JSON.stringify(selectedNode.inputs, null, 2)}
                    </pre>
                  </div>
                </div>

                {/* Outputs */}
                <div>
                  <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Outputs</h3>
                  <div className="code-block bg-emerald-50/50 border-emerald-100">
                    <pre className="text-xs font-mono text-slate-700 overflow-x-auto whitespace-pre-wrap leading-relaxed">
                      {typeof selectedNode.outputs === 'string'
                        ? selectedNode.outputs
                        : JSON.stringify(selectedNode.outputs, null, 2)}
                    </pre>
                  </div>
                </div>

                {/* Error if present */}
                {selectedNode.error && (
                  <div className="bg-red-50 border border-red-100 p-4 rounded-xl shadow-sm">
                    <h3 className="text-xs font-bold text-red-500 uppercase tracking-wider mb-2 flex items-center gap-2">
                      <AlertCircle size={14} /> Error
                    </h3>
                    <pre className="text-xs font-mono text-red-600 whitespace-pre-wrap break-all">
                      {selectedNode.error}
                    </pre>
                  </div>
                )}

                {/* Annotations & Flagging */}
                <div className="pt-6 border-t border-slate-100">
                  <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-3 flex items-center gap-2">
                    Team Notes
                  </h3>

                  <div className="mb-4 bg-slate-50 p-3 rounded-lg hover:bg-slate-100 transition-colors border border-slate-100">
                    <label className="flex items-center gap-3 text-sm cursor-pointer select-none">
                      <div className={`w-5 h-5 rounded flex items-center justify-center transition-all ${selectedNode.flagged ? 'bg-amber-400 shadow-amber-200 shadow-sm scale-110' : 'bg-white border border-slate-300'}`}>
                        {selectedNode.flagged && <AlertCircle size={14} className="text-white" />}
                      </div>
                      <input
                        type="checkbox"
                        checked={selectedNode.flagged}
                        onChange={(e) => updateAnnotation(selectedNode.annotations || '', e.target.checked)}
                        className="hidden"
                      />
                      <span className={selectedNode.flagged ? 'text-amber-600 font-semibold' : 'text-slate-500'}>
                        Flag for review
                      </span>
                    </label>
                  </div>

                  <div className="relative group">
                    <textarea
                      className="w-full h-32 bg-white border border-slate-200 rounded-xl p-4 text-sm text-slate-700 focus:border-blue-400 focus:outline-none focus:ring-4 focus:ring-blue-50 transition-all placeholder:text-slate-400 resize-none shadow-sm"
                      placeholder="Add context or instructions for your team..."
                      value={selectedNode.annotations || ''}
                      onChange={(e) => setSelectedNode({ ...selectedNode, annotations: e.target.value })}
                      onBlur={(e) => updateAnnotation(e.target.value, selectedNode.flagged)}
                    />
                    <div className="absolute bottom-3 right-3 opacity-0 group-hover:opacity-100 transition-opacity">
                      <span className="text-[10px] bg-slate-100 text-slate-500 px-2 py-1 rounded-full border border-slate-200 font-medium">Auto-saved</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

export default function AppWrapper() {
  return (
    <ReactFlowProvider>
      <App />
    </ReactFlowProvider>
  );
}
