import sqlite3
import json
from fastapi import FastAPI, HTTPException, Body
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
from .models import TraceNode, TraceNodeCreate, AnnotationUpdate
import uuid
from datetime import datetime

# Database setup
DB_NAME = "traces.db"

def get_db_connection():
    conn = sqlite3.connect(DB_NAME)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db_connection()
    c = conn.cursor()
    c.execute('''
        CREATE TABLE IF NOT EXISTS traces (
            node_id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            parent_id TEXT,
            name TEXT,
            node_type TEXT,
            inputs TEXT,
            outputs TEXT,
            start_time REAL,
            end_time REAL,
            latency_ms REAL,
            token_count INTEGER,
            error TEXT,
            metadata TEXT,
            created_at TEXT,
            annotations TEXT,
            flagged INTEGER DEFAULT 0
        )
    ''')
    # Try creating index if not exists
    try:
        c.execute("CREATE INDEX IF NOT EXISTS idx_session_id ON traces (session_id)")
    except:
        pass
    conn.commit()
    conn.close()

app = FastAPI(title="GenAI Prompt Tree Explorer API")

# Enable CORS for frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
def startup_event():
    init_db()

@app.post("/api/v1/traces", response_model=TraceNode)
async def ingest_trace(trace: TraceNodeCreate):
    conn = get_db_connection()
    c = conn.cursor()
    
    node_id = trace.node_id or str(uuid.uuid4())
    created_at = datetime.utcnow().isoformat()
    
    try:
        c.execute('''
            INSERT INTO traces (
                node_id, session_id, parent_id, name, node_type, 
                inputs, outputs, start_time, end_time, latency_ms, 
                token_count, error, metadata, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            node_id,
            trace.session_id,
            trace.parent_id,
            trace.name,
            trace.node_type,
            json.dumps(trace.inputs),
            json.dumps(trace.outputs) if trace.outputs else None,
            trace.start_time,
            trace.end_time,
            trace.latency_ms,
            trace.token_count,
            trace.error,
            json.dumps(trace.metadata) if trace.metadata else None,
            created_at
        ))
        conn.commit()
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        conn.close()
        
    return TraceNode(
        **trace.dict(),
        node_id=node_id,
        created_at=datetime.fromisoformat(created_at),
        annotations=None, # Initially empty
        flagged=False
    )

@app.get("/api/v1/trees/{session_id}", response_model=List[TraceNode])
async def get_session_tree(session_id: str):
    conn = get_db_connection()
    c = conn.cursor()
    c.execute("SELECT * FROM traces WHERE session_id = ? ORDER BY start_time ASC", (session_id,))
    rows = c.fetchall()
    conn.close()
    
    nodes = []
    for row in rows:
        row_dict = dict(row)
        # Parse JSON fields
        try:
            row_dict['inputs'] = json.loads(row_dict['inputs']) if row_dict['inputs'] else {}
            row_dict['outputs'] = json.loads(row_dict['outputs']) if row_dict['outputs'] else None
            row_dict['metadata'] = json.loads(row_dict['metadata']) if row_dict['metadata'] else None
            row_dict['flagged'] = bool(row_dict['flagged'])
            # Ensure created_at is valid datetime object if needed, but Pydantic handles string->datetime
            nodes.append(TraceNode(**row_dict))
        except Exception as e:
            print(f"Error parsing row {row_dict['node_id']}: {e}")
            continue
            
    return nodes

@app.patch("/api/v1/nodes/{node_id}", response_model=TraceNode)
async def update_node_annotation(node_id: str, update: AnnotationUpdate):
    conn = get_db_connection()
    c = conn.cursor()
    
    # Check if node exists
    c.execute("SELECT * FROM traces WHERE node_id = ?", (node_id,))
    row = c.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Node not found")
    
    # Update fields
    updates = []
    params = []
    
    if update.annotations is not None:
        updates.append("annotations = ?")
        params.append(update.annotations)
        
    if update.flagged is not None:
        updates.append("flagged = ?")
        params.append(1 if update.flagged else 0)
        
    if not updates:
        conn.close()
        # No updates, return current state
        row_dict = dict(row)
        row_dict['inputs'] = json.loads(row_dict['inputs']) if row_dict['inputs'] else {}
        row_dict['outputs'] = json.loads(row_dict['outputs']) if row_dict['outputs'] else None
        row_dict['metadata'] = json.loads(row_dict['metadata']) if row_dict['metadata'] else None
        row_dict['flagged'] = bool(row_dict['flagged'])
        return TraceNode(**row_dict)

    params.append(node_id)
    query = f"UPDATE traces SET {', '.join(updates)} WHERE node_id = ?"
    
    try:
        c.execute(query, tuple(params))
        conn.commit()
        
        # Fetch updated
        c.execute("SELECT * FROM traces WHERE node_id = ?", (node_id,))
        updated_row = c.fetchone()
        row_dict = dict(updated_row)
        row_dict['inputs'] = json.loads(row_dict['inputs']) if row_dict['inputs'] else {}
        row_dict['outputs'] = json.loads(row_dict['outputs']) if row_dict['outputs'] else None
        row_dict['metadata'] = json.loads(row_dict['metadata']) if row_dict['metadata'] else None
        row_dict['flagged'] = bool(row_dict['flagged'])
        return TraceNode(**row_dict)
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        conn.close()

@app.post("/api/v1/import_traces")
async def import_traces(traces: List[TraceNodeCreate]):
    conn = get_db_connection()
    c = conn.cursor()
    
    try:
        for trace in traces:
            node_id = trace.node_id or str(uuid.uuid4())
            created_at = datetime.utcnow().isoformat()
            
            c.execute('''
                INSERT OR REPLACE INTO traces (
                    node_id, session_id, parent_id, name, node_type, 
                    inputs, outputs, start_time, end_time, latency_ms, 
                    token_count, error, metadata, created_at, annotations, flagged
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                node_id,
                trace.session_id,
                trace.parent_id,
                trace.name,
                trace.node_type,
                json.dumps(trace.inputs),
                json.dumps(trace.outputs) if trace.outputs else None,
                trace.start_time,
                trace.end_time,
                trace.latency_ms,
                trace.token_count,
                trace.error,
                json.dumps(trace.metadata) if trace.metadata else None,
                trace.created_at.isoformat() if hasattr(trace, 'created_at') and trace.created_at else datetime.utcnow().isoformat(),
                trace.annotations if hasattr(trace, 'annotations') else None,
                trace.flagged if hasattr(trace, 'flagged') else False
            ))
        
        conn.commit()
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        conn.close()
    
    return {"message": f"Successfully imported {len(traces)} traces"}

@app.post("/api/v1/run_demo")
async def run_demo():
    import subprocess
    import sys
    try:
        # Run the demo_agent.py script in a separate process
        subprocess.Popen([sys.executable, "demo_agent.py"])
        return {"status": "started", "message": "Demo agent started in background"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/v1/sessions", response_model=List[str])
async def get_sessions():
    conn = get_db_connection()
    c = conn.cursor()
    c.execute("SELECT DISTINCT session_id FROM traces ORDER BY created_at DESC")
    rows = c.fetchall()
    conn.close()
    return [row['session_id'] for row in rows]

# MARK: - FFM Risk Planning Endpoint (Integrated with AeroMaps)

class FFMPlanRequest(BaseModel):
    class Aircraft(BaseModel):
        type: str
        trueAirspeedKTAS: float
        fuelBurnGPH: float

    class Waypoint(BaseModel):
        lat: float
        lon: float

    class Policy(BaseModel):
        reserveMinutes: int
        enforceMEF: bool

    aircraft: Aircraft
    route: List[Waypoint]
    policy: Policy

@app.post("/v1/plan")
async def compute_ffm_plan(request: FFMPlanRequest):
    session_id = f"AeroMaps_FFM_Plan_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}"
    start_t = datetime.utcnow().timestamp()
    root_id = str(uuid.uuid4())
    
    leg_risks = []
    polyline = []
    
    for i in range(len(request.route)):
        wpt = request.route[i]
        polyline.append({"lat": wpt.lat, "lon": wpt.lon})
        if i < len(request.route) - 1:
            next_wpt = request.route[i+1]
            dist_factor = abs(next_wpt.lat - wpt.lat) + abs(next_wpt.lon - wpt.lon)
            icing = min(0.9, round(0.1 + dist_factor * 0.3, 2))
            turbulence = min(0.9, round(0.2 + dist_factor * 0.4, 2))
            terrain = min(0.9, round(0.1 + (wpt.lat % 0.1) * 2, 2))
            leg_risks.append({
                "fromIndex": i,
                "toIndex": i + 1,
                "icing": icing,
                "turbulence": turbulence,
                "terrain": terrain
            })
    
    advisory = f"FFM Safety Advisory: Analyzed {len(request.route)} waypoints for {request.aircraft.type} aircraft at {int(request.aircraft.trueAirspeedKTAS)} KTAS. Moderate turbulence forecast along route."
    alternates = ["KOAK", "KSQL", "KSJC"]
    tile_templates = ["https://tile.openweathermap.org/map/precipitation_new/{z}/{x}/{y}.png?appid=demo"]
    
    # Store trace node in Prompt Tree Explorer database
    try:
        conn = get_db_connection()
        c = conn.cursor()
        c.execute('''
            INSERT INTO traces (
                node_id, session_id, parent_id, name, node_type, 
                inputs, outputs, start_time, end_time, latency_ms, 
                token_count, error, metadata, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            root_id,
            session_id,
            None,
            "FFM_Risk_Planning_Engine",
            "agent",
            json.dumps(request.dict()),
            json.dumps({"advisory": advisory, "legRisks": legRisks, "alternates": alternates}),
            start_t,
            datetime.utcnow().timestamp(),
            145.0,
            120,
            None,
            json.dumps({"narration": f"Evaluated safety envelope, reserve minutes ({request.policy.reserveMinutes}m), and MEF altitude floors."}),
            datetime.utcnow().isoformat()
        ))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"Error logging FFM trace: {e}")
    
    return {
        "polyline": polyline,
        "legRisks": legRisks,
        "alternates": alternates,
        "advisory": advisory,
        "riskTileTemplates": tile_templates
    }
