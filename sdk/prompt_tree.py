import functools
import time
import uuid
import threading
import queue
import atexit
import inspect
import json
import os
import contextvars
import requests
from typing import Optional, Any, Dict

# Global tracer instance placeholder
_TRACER: Optional['Tracer'] = None

# ContextVar for managing parent-child relationships automatically
parent_context: contextvars.ContextVar[Optional[str]] = contextvars.ContextVar("parent_context", default=None)

class Tracer:
    """
    Main tracer class that handles session management and asynchronous logging.
    """
    def __init__(self, session_name: str, api_host: str = "http://localhost:8000"):
        global _TRACER
        self.session_id = f"{session_name}_{uuid.uuid4().hex[:8]}"
        self.api_host = api_host.rstrip("/")
        self.queue: queue.Queue = queue.Queue()
        self.shutdown_flag = threading.Event()
        
        # Start background worker thread
        self.worker_thread = threading.Thread(target=self._worker, daemon=True)
        self.worker_thread.start()
        
        _TRACER = self
        print(f"🌳 Prompt Tree Tracer initialized. Session ID: {self.session_id}")
        
        # Ensure clean shutdown
        atexit.register(self.shutdown)

    def _worker(self):
        """Background worker to drain the queue and send traces to API."""
        while not self.shutdown_flag.is_set() or not self.queue.empty():
            try:
                # Wait for item with timeout to check shutdown flag periodically
                item = self.queue.get(timeout=0.5)
            except queue.Empty:
                continue

            if item is None:
                break
            
            try:
                # Add session_id if not present (though decorator likely adds it)
                if "session_id" not in item:
                    item["session_id"] = self.session_id
                
                requests.post(f"{self.api_host}/api/v1/traces", json=item, timeout=5)
            except Exception as e:
                # Silently fail to avoid crashing main app, maybe log to stderr
                # print(f"Warning: Failed to send trace: {e}")
                pass
            finally:
                self.queue.task_done()

    def log_node(self, node_data: Dict[str, Any]):
        node_data["session_id"] = self.session_id
        self.queue.put(node_data)
    
    def shutdown(self):
        """Stop the worker thread gracefully."""
        self.shutdown_flag.set()
        # Wait for queue to empty? Ideally yes.
        if self.worker_thread.is_alive():
            self.worker_thread.join(timeout=2.0)

def trace_node(name: Optional[str] = None, inputs_to_capture: Optional[list] = None):
    """
    Decorator to trace a function execution as a node in the prompt tree.
    """
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            if _TRACER is None:
                return func(*args, **kwargs)

            # Determine parent ID from context
            parent_id = parent_context.get()
            
            # Generate new node ID
            node_id = str(uuid.uuid4())
            
            # Set current node as parent for subsequent calls
            token = parent_context.set(node_id)
            
            start_time = time.time()
            
            # Capture inputs
            captured_inputs = {}
            try:
                sig = inspect.signature(func)
                bound_args = sig.bind(*args, **kwargs)
                bound_args.apply_defaults()
                # Basic string serialization for inputs
                for k, v in bound_args.arguments.items():
                    try:
                        captured_inputs[k] = v if isinstance(v, (str, int, float, bool, list, dict)) else str(v)
                    except:
                        captured_inputs[k] = str(v)
            except Exception:
                captured_inputs = {"args": str(args), "kwargs": str(kwargs)}

            error = None
            output = None
            
            try:
                result = func(*args, **kwargs)
                try:
                    output = result if isinstance(result, (str, int, float, bool, list, dict)) else str(result)
                except:
                    output = str(result)
                return result
            except Exception as e:
                error = str(e)
                raise
            finally:
                # Reset context
                parent_context.reset(token)
                
                end_time = time.time()
                latency_ms = (end_time - start_time) * 1000
                
                payload = {
                    "node_id": node_id,
                    "parent_id": parent_id,
                    "name": name or func.__name__,
                    "node_type": "llm_call", # Default, could be configurable
                    "inputs": captured_inputs,
                    "outputs": output,
                    "start_time": start_time,
                    "end_time": end_time,
                    "latency_ms": latency_ms,
                    "error": error,
                    "token_count": int(len(str(output))/4) if output else 0, # Rough estimation
                    "metadata": {}
                }
                
                _TRACER.log_node(payload)
        return wrapper
    return decorator
