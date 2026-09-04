import axios from 'axios';
import type { TraceNode, AnnotationUpdate } from './types';

const API_BASE = 'http://localhost:8081/api/v1';

export const fetchSessions = async (): Promise<string[]> => {
    try {
        const res = await axios.get(`${API_BASE}/sessions`);
        return res.data;
    } catch (error) {
        console.error("Failed to fetch sessions", error);
        return [];
    }
};

export const fetchSessionTree = async (sessionId: string): Promise<TraceNode[]> => {
    try {
        const res = await axios.get(`${API_BASE}/trees/${sessionId}`);
        return res.data;
    } catch (error) {
        console.error("Failed to fetch session tree", error);
        return [];
    }
};

export const updateNodeAnnotation = async (nodeId: string, update: AnnotationUpdate): Promise<TraceNode> => {
    const res = await axios.patch(`${API_BASE}/nodes/${nodeId}`, update);
    return res.data;
};

export const runDemo = async (): Promise<void> => {
    await axios.post(`${API_BASE}/run_demo`);
};

export const importTraces = async (traces: any[]): Promise<void> => {
    await axios.post(`${API_BASE}/import_traces`, traces);
};
