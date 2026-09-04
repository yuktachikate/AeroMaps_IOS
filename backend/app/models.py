from datetime import datetime
from typing import Optional, List, Dict, Any, Union
from pydantic import BaseModel, ConfigDict
import uuid

class TraceNodeCreate(BaseModel):
    session_id: str
    parent_id: Optional[str] = None
    node_id: Optional[str] = None  # If not provided, backend generates it
    name: str # e.g. "Extract_Context"
    node_type: str = "llm_call"  # llm_call, tool_call, logic, etc.
    inputs: Dict[str, Any]
    outputs: Optional[Any] = None
    start_time: float # Unix timestamp
    end_time: Optional[float] = None
    latency_ms: Optional[float] = None
    token_count: Optional[int] = None
    error: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None
    created_at: Optional[datetime] = None
    annotations: Optional[str] = None
    flagged: Optional[bool] = False

class TraceNode(TraceNodeCreate):
    node_id: str
    created_at: datetime
    annotations: Optional[str] = None
    flagged: bool = False

    model_config = ConfigDict(from_attributes=True)

class AnnotationUpdate(BaseModel):
    annotations: Optional[str] = None
    flagged: Optional[bool] = None

class SessionData(BaseModel):
    session_id: str
    nodes: List[TraceNode]
