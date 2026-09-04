export interface TraceNode {
    node_id: string;
    session_id: string;
    parent_id: string | null;
    name: string;
    node_type: string;
    inputs: Record<string, any>;
    outputs: any;
    start_time: number;
    end_time: number | null;
    latency_ms: number | null;
    token_count: number | null;
    error: string | null;
    metadata: Record<string, any> | null;
    created_at: string;
    annotations: string | null;
    flagged: boolean;
}

export interface AnnotationUpdate {
    annotations?: string;
    flagged?: boolean;
}
