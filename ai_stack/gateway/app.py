from __future__ import annotations

import copy
import json
import os
import sqlite3
import time
import uuid
from pathlib import Path
from typing import Any

import httpx
from fastapi import Depends, FastAPI, File, Header, HTTPException, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel, Field

APP_ROOT = Path(os.environ.get("TMP_MEDIA_ROOT", "/opt/tmp-media-ai"))
TEMPLATE_DIR = Path(os.environ.get("TMP_MEDIA_TEMPLATE_DIR", APP_ROOT / "ai_stack" / "templates"))
INPUT_DIR = Path(os.environ.get("TMP_MEDIA_INPUT_DIR", APP_ROOT / "ComfyUI" / "input"))
DB_PATH = Path(os.environ.get("TMP_MEDIA_DB", APP_ROOT / "state" / "jobs.sqlite3"))
WORKERS = [x.strip().rstrip("/") for x in os.environ.get("TMP_MEDIA_WORKERS", "http://127.0.0.1:8188").split(",") if x.strip()]
API_KEY = os.environ.get("TMP_MEDIA_API_KEY", "")
REQUEST_TIMEOUT = float(os.environ.get("TMP_MEDIA_TIMEOUT", "30"))

app = FastAPI(
    title="TMP Media AI Gateway",
    version="0.1.0",
    description="AI-ready gateway for ComfyUI image, video, audio and workflow execution.",
)


def require_key(x_api_key: str | None = Header(default=None)) -> None:
    if API_KEY and x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="invalid API key")


def db() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS jobs (
            id TEXT PRIMARY KEY,
            prompt_id TEXT NOT NULL,
            worker TEXT NOT NULL,
            template_id TEXT,
            created REAL NOT NULL
        )
        """
    )
    conn.commit()
    return conn


class JobRequest(BaseModel):
    template_id: str
    parameters: dict[str, Any] = Field(default_factory=dict)
    client_id: str | None = None


class RawWorkflowRequest(BaseModel):
    workflow: dict[str, Any]
    client_id: str | None = None


class ValidateRequest(BaseModel):
    workflow: dict[str, Any]


def load_templates() -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    if not TEMPLATE_DIR.exists():
        return result
    for path in sorted(TEMPLATE_DIR.glob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            continue
        template_id = data.get("id")
        if template_id and isinstance(data.get("workflow"), dict):
            result[template_id] = data
    return result


def coerce(value: Any, spec: dict[str, Any]) -> Any:
    typ = spec.get("type")
    if typ == "int":
        value = int(value)
    elif typ == "float":
        value = float(value)
    elif typ == "bool":
        if isinstance(value, str):
            value = value.lower() in {"1", "true", "yes", "on"}
        else:
            value = bool(value)
    elif typ == "string":
        value = str(value)

    if isinstance(value, (int, float)):
        if "min" in spec:
            value = max(value, spec["min"])
        if "max" in spec:
            value = min(value, spec["max"])
    if "choices" in spec and value not in spec["choices"]:
        raise HTTPException(400, f"invalid value for {spec.get('label', 'parameter')}: {value}")
    return value


def render_template(template: dict[str, Any], params: dict[str, Any]) -> dict[str, Any]:
    workflow = copy.deepcopy(template["workflow"])
    specs: dict[str, dict[str, Any]] = template.get("parameters", {})

    for name, spec in specs.items():
        if name in params:
            value = params[name]
        elif "default" in spec:
            value = spec["default"]
        elif spec.get("required"):
            raise HTTPException(status_code=400, detail=f"missing required parameter: {name}")
        else:
            continue
        value = coerce(value, spec)
        node_id = str(spec["node"])
        input_name = spec["input"]
        if node_id not in workflow:
            raise HTTPException(status_code=500, detail=f"template node missing: {node_id}")
        workflow[node_id].setdefault("inputs", {})[input_name] = value

    unknown = sorted(set(params) - set(specs))
    if unknown:
        raise HTTPException(status_code=400, detail=f"unknown parameters: {', '.join(unknown)}")
    return workflow


async def worker_queue(worker: str) -> tuple[int, int]:
    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        r = await client.get(f"{worker}/queue")
        r.raise_for_status()
        data = r.json()
    running = len(data.get("queue_running", []))
    pending = len(data.get("queue_pending", []))
    return running, pending


async def choose_worker() -> str:
    candidates: list[tuple[int, int, str]] = []
    for worker in WORKERS:
        try:
            running, pending = await worker_queue(worker)
            candidates.append((running + pending, running, worker))
        except Exception:
            continue
    if not candidates:
        raise HTTPException(status_code=503, detail="no ComfyUI worker reachable")
    candidates.sort()
    return candidates[0][2]


async def object_info(worker: str) -> dict[str, Any]:
    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        r = await client.get(f"{worker}/object_info")
        r.raise_for_status()
        return r.json()


async def validate_workflow(workflow: dict[str, Any], worker: str) -> dict[str, Any]:
    info = await object_info(worker)
    missing: list[str] = []
    malformed: list[str] = []
    for node_id, node in workflow.items():
        if not isinstance(node, dict):
            malformed.append(str(node_id))
            continue
        class_type = node.get("class_type")
        if not class_type:
            malformed.append(str(node_id))
        elif class_type not in info:
            missing.append(class_type)
    return {
        "ok": not missing and not malformed,
        "missing_node_types": sorted(set(missing)),
        "malformed_nodes": sorted(set(malformed)),
        "node_count": len(workflow),
        "worker": worker,
    }


async def submit(workflow: dict[str, Any], template_id: str | None, client_id: str | None) -> dict[str, Any]:
    worker = await choose_worker()
    validation = await validate_workflow(workflow, worker)
    if not validation["ok"]:
        raise HTTPException(status_code=400, detail={"message": "workflow validation failed", **validation})

    payload: dict[str, Any] = {"prompt": workflow}
    if client_id:
        payload["client_id"] = client_id

    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        r = await client.post(f"{worker}/prompt", json=payload)
        if r.status_code >= 400:
            raise HTTPException(status_code=r.status_code, detail=r.text)
        result = r.json()

    prompt_id = result.get("prompt_id")
    if not prompt_id:
        raise HTTPException(status_code=502, detail=f"ComfyUI returned no prompt_id: {result}")

    job_id = str(uuid.uuid4())
    conn = db()
    conn.execute(
        "INSERT INTO jobs(id,prompt_id,worker,template_id,created) VALUES(?,?,?,?,?)",
        (job_id, prompt_id, worker, template_id, time.time()),
    )
    conn.commit()
    conn.close()
    return {"job_id": job_id, "prompt_id": prompt_id, "worker": worker, "template_id": template_id}


def get_job(job_id: str) -> sqlite3.Row:
    conn = db()
    row = conn.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
    conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="job not found")
    return row


@app.get("/")
async def root() -> dict[str, Any]:
    return {"service": "TMP Media AI Gateway", "version": app.version, "docs": "/docs"}


@app.get("/api/v1/health", dependencies=[Depends(require_key)])
async def health() -> dict[str, Any]:
    workers = []
    for worker in WORKERS:
        try:
            running, pending = await worker_queue(worker)
            workers.append({"url": worker, "ok": True, "running": running, "pending": pending})
        except Exception as exc:
            workers.append({"url": worker, "ok": False, "error": str(exc)})
    return {"ok": any(x["ok"] for x in workers), "workers": workers}


@app.get("/api/v1/workers", dependencies=[Depends(require_key)])
async def workers() -> list[dict[str, Any]]:
    return (await health())["workers"]


@app.get("/api/v1/templates", dependencies=[Depends(require_key)])
async def templates() -> list[dict[str, Any]]:
    result = []
    for template in load_templates().values():
        result.append({
            "id": template["id"],
            "name": template.get("name", template["id"]),
            "kind": template.get("kind", "workflow"),
            "description": template.get("description", ""),
            "parameters": template.get("parameters", {}),
        })
    return result


@app.get("/api/v1/templates/{template_id}", dependencies=[Depends(require_key)])
async def template(template_id: str) -> dict[str, Any]:
    item = load_templates().get(template_id)
    if not item:
        raise HTTPException(404, "template not found")
    return {k: v for k, v in item.items() if k != "workflow"}


@app.get("/api/v1/nodes", dependencies=[Depends(require_key)])
async def nodes() -> dict[str, Any]:
    worker = await choose_worker()
    info = await object_info(worker)
    return {"worker": worker, "nodes": info}


@app.post("/api/v1/workflows/validate", dependencies=[Depends(require_key)])
async def validate(req: ValidateRequest) -> dict[str, Any]:
    worker = await choose_worker()
    return await validate_workflow(req.workflow, worker)


@app.post("/api/v1/jobs", dependencies=[Depends(require_key)])
async def create_job(req: JobRequest) -> dict[str, Any]:
    template = load_templates().get(req.template_id)
    if not template:
        raise HTTPException(404, "template not found")
    workflow = render_template(template, req.parameters)
    return await submit(workflow, req.template_id, req.client_id)


@app.post("/api/v1/jobs/raw", dependencies=[Depends(require_key)])
async def create_raw_job(req: RawWorkflowRequest) -> dict[str, Any]:
    return await submit(req.workflow, None, req.client_id)


@app.get("/api/v1/jobs/{job_id}", dependencies=[Depends(require_key)])
async def job_status(job_id: str) -> dict[str, Any]:
    row = get_job(job_id)
    worker = row["worker"]
    prompt_id = row["prompt_id"]
    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        hist_r = await client.get(f"{worker}/history/{prompt_id}")
        hist_r.raise_for_status()
        history = hist_r.json()
        queue_r = await client.get(f"{worker}/queue")
        queue_r.raise_for_status()
        queue = queue_r.json()

    if prompt_id in history:
        state = "completed"
        item = history[prompt_id]
        status_data = item.get("status", {})
        if status_data.get("status_str") == "error" or status_data.get("completed") is False:
            state = "error"
    else:
        running_ids = {str(x[1]) for x in queue.get("queue_running", []) if len(x) > 1}
        pending_ids = {str(x[1]) for x in queue.get("queue_pending", []) if len(x) > 1}
        if prompt_id in running_ids:
            state = "running"
        elif prompt_id in pending_ids:
            state = "queued"
        else:
            state = "unknown"
        item = None

    return {
        "job_id": job_id,
        "prompt_id": prompt_id,
        "template_id": row["template_id"],
        "worker": worker,
        "state": state,
        "history": item,
    }


@app.get("/api/v1/jobs/{job_id}/outputs", dependencies=[Depends(require_key)])
async def job_outputs(job_id: str) -> dict[str, Any]:
    status = await job_status(job_id)
    item = status.get("history") or {}
    outputs = item.get("outputs", {})
    files: list[dict[str, Any]] = []
    for node_id, node_output in outputs.items():
        for kind in ("images", "audio", "video", "gifs"):
            for obj in node_output.get(kind, []) or []:
                if isinstance(obj, dict) and obj.get("filename"):
                    files.append({"node_id": node_id, "kind": kind, **obj})
    return {"job_id": job_id, "state": status["state"], "files": files, "raw_outputs": outputs}


@app.get("/api/v1/jobs/{job_id}/file", dependencies=[Depends(require_key)])
async def job_file(job_id: str, filename: str, subfolder: str = "", type: str = "output") -> Response:
    row = get_job(job_id)
    params = {"filename": filename, "subfolder": subfolder, "type": type}
    async with httpx.AsyncClient(timeout=None) as client:
        r = await client.get(f"{row['worker']}/view", params=params)
        if r.status_code >= 400:
            raise HTTPException(status_code=r.status_code, detail=r.text)
        return Response(content=r.content, media_type=r.headers.get("content-type", "application/octet-stream"))


@app.post("/api/v1/assets", dependencies=[Depends(require_key)])
async def upload_asset(file: UploadFile = File(...)) -> dict[str, Any]:
    INPUT_DIR.mkdir(parents=True, exist_ok=True)
    original = Path(file.filename or "asset.bin").name
    stem = Path(original).stem[:80] or "asset"
    suffix = Path(original).suffix[:12]
    name = f"eva_{int(time.time())}_{uuid.uuid4().hex[:8]}_{stem}{suffix}"
    target = INPUT_DIR / name
    with target.open("wb") as out:
        while chunk := await file.read(1024 * 1024):
            out.write(chunk)
    return {"filename": name, "path": str(target), "size": target.stat().st_size}
