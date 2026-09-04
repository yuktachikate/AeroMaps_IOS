import { Handle, Position, type NodeProps } from 'reactflow';
import type { TraceNode } from '../types';
import { Clock, AlertTriangle, Box, Activity } from 'lucide-react';
import React from 'react';

const CustomNode = ({ data }: NodeProps<TraceNode>) => {
    const isError = !!data.error;
    const isFlagged = data.flagged;

    return (
        <div className={`
      relative min-w-[220px] bg-white rounded-xl border transition-all duration-300
      ${isError ? 'border-red-500 shadow-red-200 shadow-md' : 'border-slate-200 hover:border-blue-400 hover:shadow-lg hover:shadow-blue-100'}
      ${isFlagged ? 'ring-2 ring-yellow-400' : ''}
    `}>
            {/* Input Handle */}
            <Handle
                type="target"
                position={Position.Top}
                className="!bg-slate-400 !w-3 !h-3 !-top-1.5 !border-2 !border-white"
            />

            <div className="p-3">
                {/* Header */}
                <div className="flex items-center justify-between mb-2 pb-2 border-b border-slate-100">
                    <div className="flex items-center gap-2">
                        {isError ? (
                            <AlertTriangle className="w-4 h-4 text-red-500" />
                        ) : (
                            <Box className="w-4 h-4 text-blue-500" />
                        )}
                        <span className="text-sm font-semibold text-slate-800 truncate max-w-[140px]" title={data.name}>
                            {data.name}
                        </span>
                    </div>
                    <span className="text-[10px] uppercase tracking-wider font-bold text-slate-500 bg-slate-50 px-2 py-0.5 rounded-full border border-slate-100">
                        {data.node_type}
                    </span>
                </div>

                {/* Content Preview (Input Snippet) */}
                {data.inputs && (
                    <div className="mb-2 text-xs text-slate-500 font-mono bg-slate-50 p-2 rounded border border-slate-100 truncate">
                        {JSON.stringify(data.inputs).slice(0, 35)}...
                    </div>
                )}

                {/* Footer Metrics */}
                <div className="flex items-center justify-between text-[11px] text-slate-400 font-medium">
                    <div className="flex items-center gap-1.5" title="Latency">
                        <Clock className="w-3.5 h-3.5 text-slate-400" />
                        <span className={data.latency_ms && data.latency_ms > 1000 ? "text-amber-500 font-bold" : ""}>
                            {data.latency_ms ? `${Math.round(data.latency_ms)}ms` : '...'}
                        </span>
                    </div>

                    {data.token_count && (
                        <div className="flex items-center gap-1.5" title="Tokens">
                            <Activity className="w-3.5 h-3.5 text-slate-400" />
                            <span>{data.token_count}</span>
                        </div>
                    )}
                </div>
            </div>

            {/* Output Handle */}
            <Handle
                type="source"
                position={Position.Bottom}
                className="!bg-slate-400 !w-3 !h-3 !-bottom-1.5 !border-2 !border-white"
            />

            {/* Error Badge */}
            {isError && (
                <div className="absolute -top-2 -right-2 bg-red-500 text-white text-[10px] font-bold px-2 py-0.5 rounded-full shadow-lg animate-bounce">
                    ERR
                </div>
            )}
        </div>
    );
};

export default React.memo(CustomNode);
