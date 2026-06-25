import asyncio
import contextlib
import logging
import os
import re
import tempfile
import time
import uuid
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse

import aiohttp
from aiohttp import web

import folder_paths
from server import PromptServer


WEB_DIRECTORY = "./web"
NODE_CLASS_MAPPINGS = {}

ALLOWED_HOST_SUFFIXES = (
    "huggingface.co",
    "civitai.com",
    "civitai.red",
    "github.com",
)
ALLOWED_EXTENSIONS = (".safetensors", ".sft", ".ckpt", ".pth", ".pt")
MAX_FILENAME_LENGTH = 240
CHUNK_SIZE = 1024 * 1024

download_tasks: dict[str, asyncio.Task] = {}
download_ids_by_key: dict[str, str] = {}
download_statuses: dict[str, dict] = {}


def json_error(status: int, message: str) -> web.Response:
    return web.json_response({"ok": False, "error": message}, status=status)


def is_allowed_url(url: str) -> bool:
    parsed = urlparse(url)
    if parsed.scheme != "https":
        return False
    host = (parsed.hostname or "").lower()
    return any(host == suffix or host.endswith(f".{suffix}") for suffix in ALLOWED_HOST_SUFFIXES)


def with_auth(url: str) -> tuple[str, dict[str, str]]:
    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    headers: dict[str, str] = {}

    if host == "huggingface.co" or host.endswith(".huggingface.co"):
        token = os.environ.get("HF_TOKEN")
        if token:
            headers["Authorization"] = f"Bearer {token}"

    if host == "civitai.com" or host.endswith(".civitai.com"):
        token = os.environ.get("CIVITAI_API_KEY")
        query = dict(parse_qsl(parsed.query, keep_blank_values=True))
        if token and "token" not in query:
            query["token"] = token
            url = urlunparse(parsed._replace(query=urlencode(query)))

    return url, headers


def sanitize_filename(filename: str) -> str:
    filename = filename.split("?", 1)[0].strip().replace("\\", "/").split("/")[-1]
    filename = re.sub(r"[^A-Za-z0-9._() +-]", "_", filename)
    filename = filename.strip(" .")
    if not filename or filename in {".", ".."}:
        raise ValueError("invalid filename")
    if len(filename) > MAX_FILENAME_LENGTH:
        stem = Path(filename).stem[: MAX_FILENAME_LENGTH - len(Path(filename).suffix)]
        filename = f"{stem}{Path(filename).suffix}"
    if not filename.lower().endswith(ALLOWED_EXTENSIONS):
        raise ValueError("unsupported model extension")
    return filename


def resolve_destination(directory: str, filename: str) -> Path:
    normalized = directory.strip().replace("\\", "/").strip("/")
    if not normalized or ".." in normalized.split("/"):
        raise ValueError("invalid model directory")

    parts = normalized.split("/")
    model_type = folder_paths.map_legacy(parts[0])
    remainder = parts[1:]
    entry = folder_paths.folder_names_and_paths.get(model_type)
    if entry is None:
        raise ValueError(f"unknown model directory: {model_type}")

    candidates = [Path(path) for path in entry[0]]
    preferred = next((path for path in candidates if path.name == model_type), candidates[0])
    destination_dir = preferred.joinpath(*remainder)
    destination = destination_dir / filename
    resolved_dir = destination_dir.resolve()
    resolved_destination = destination.resolve()

    if resolved_destination.parent != resolved_dir:
        raise ValueError("invalid destination path")

    return resolved_destination


def public_status(download_id: str) -> dict:
    status = download_statuses[download_id].copy()
    total = status.get("total_bytes") or 0
    received = status.get("received_bytes") or 0
    if status.get("status") == "completed":
        status["progress"] = 1
    else:
        status["progress"] = received / total if total > 0 else None
    return status


async def download_model(
    download_id: str,
    url: str,
    filename: str,
    destination: Path,
    headers: dict[str, str],
) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(
        prefix=f".{destination.name}.",
        suffix=".part",
        dir=str(destination.parent),
    )
    os.close(fd)
    temp_path = Path(temp_name)

    try:
        status = download_statuses[download_id]
        status["status"] = "downloading"
        logging.info("[runpod-model-downloader] started %s -> %s", url, destination)

        timeout = aiohttp.ClientTimeout(total=None, connect=60, sock_read=300)
        async with aiohttp.ClientSession(timeout=timeout, headers=headers) as session:
            async with session.get(url, allow_redirects=True) as response:
                response.raise_for_status()
                content_length = response.headers.get("content-length")
                if content_length and content_length.isdigit():
                    status["total_bytes"] = int(content_length)

                last_logged_percent = -10
                last_logged_time = time.monotonic()
                with temp_path.open("wb") as handle:
                    async for chunk in response.content.iter_chunked(CHUNK_SIZE):
                        handle.write(chunk)
                        status["received_bytes"] += len(chunk)

                        total = status.get("total_bytes") or 0
                        now = time.monotonic()
                        if total > 0:
                            percent = int(status["received_bytes"] * 100 / total)
                            if percent >= last_logged_percent + 10 or percent == 100:
                                logging.info(
                                    "[runpod-model-downloader] %s %d%% (%d/%d bytes)",
                                    filename,
                                    percent,
                                    status["received_bytes"],
                                    total,
                                )
                                last_logged_percent = percent
                                last_logged_time = now
                        elif now - last_logged_time >= 30:
                            logging.info(
                                "[runpod-model-downloader] %s %d bytes downloaded",
                                filename,
                                status["received_bytes"],
                            )
                            last_logged_time = now
        os.replace(temp_path, destination)
        status["status"] = "completed"
        status["received_bytes"] = status.get("total_bytes") or status["received_bytes"]
        logging.info("[runpod-model-downloader] downloaded %s -> %s", url, destination)
    except Exception as exc:
        download_statuses[download_id]["status"] = "error"
        download_statuses[download_id]["error"] = str(exc)
        temp_path.unlink(missing_ok=True)
        logging.exception("[runpod-model-downloader] failed to download %s", url)
        raise


def cleanup_task(key: str, task: asyncio.Task) -> None:
    download_tasks.pop(key, None)
    download_ids_by_key.pop(key, None)
    with contextlib.suppress(asyncio.CancelledError, Exception):
        task.result()


@PromptServer.instance.routes.post("/runpod-model-downloader/download")
async def start_download(request: web.Request) -> web.Response:
    try:
        payload = await request.json()
    except Exception:
        return json_error(400, "invalid JSON body")

    url = str(payload.get("url", ""))
    directory = str(payload.get("directory", ""))

    if not is_allowed_url(url):
        return json_error(400, "unsupported model URL")

    try:
        filename = sanitize_filename(str(payload.get("filename", "")))
        destination = resolve_destination(directory, filename)
    except ValueError as exc:
        return json_error(400, str(exc))

    url, headers = with_auth(url)
    key = f"{url}\n{destination}"
    if destination.exists():
        return web.json_response(
            {
                "ok": True,
                "status": "exists",
                "path": str(destination),
                "received_bytes": destination.stat().st_size,
                "total_bytes": destination.stat().st_size,
                "progress": 1,
            },
            status=200,
        )

    existing = download_tasks.get(key)
    if existing and not existing.done():
        download_id = download_ids_by_key[key]
        return web.json_response(
            {"ok": True, **public_status(download_id)},
            status=202,
        )

    download_id = uuid.uuid4().hex
    download_statuses[download_id] = {
        "id": download_id,
        "status": "queued",
        "url": url,
        "filename": filename,
        "directory": directory,
        "path": str(destination),
        "received_bytes": 0,
        "total_bytes": None,
        "error": None,
    }

    task = asyncio.create_task(download_model(download_id, url, filename, destination, headers))
    download_tasks[key] = task
    download_ids_by_key[key] = download_id
    task.add_done_callback(lambda done: cleanup_task(key, done))

    return web.json_response(
        {"ok": True, **public_status(download_id)},
        status=202,
    )


@PromptServer.instance.routes.get("/runpod-model-downloader/status/{download_id}")
async def get_download_status(request: web.Request) -> web.Response:
    download_id = request.match_info["download_id"]
    if download_id not in download_statuses:
        return json_error(404, "unknown download id")
    return web.json_response({"ok": True, **public_status(download_id)})
