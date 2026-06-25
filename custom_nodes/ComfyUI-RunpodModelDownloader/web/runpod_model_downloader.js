(function () {
  "use strict";

  if (window.__runpodModelDownloaderInstalled) return;
  window.__runpodModelDownloaderInstalled = true;

  if (window.__comfyDesktop2 && typeof window.__comfyDesktop2.downloadModel === "function") {
    return;
  }

  const downloads = new Map();
  let panel;
  let list;

  function formatBytes(bytes) {
    if (!Number.isFinite(bytes)) return "";
    const units = ["B", "KB", "MB", "GB", "TB"];
    let value = bytes;
    let unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit += 1;
    }
    return `${value >= 10 || unit === 0 ? value.toFixed(0) : value.toFixed(1)} ${units[unit]}`;
  }

  function ensurePanel() {
    if (panel) return;

    panel = document.createElement("section");
    panel.style.cssText = [
      "position:fixed",
      "right:16px",
      "bottom:16px",
      "z-index:999999",
      "width:min(380px,calc(100vw - 32px))",
      "max-height:45vh",
      "overflow:auto",
      "border:1px solid rgba(255,255,255,0.14)",
      "border-radius:8px",
      "background:rgba(18,18,22,0.96)",
      "box-shadow:0 12px 40px rgba(0,0,0,0.35)",
      "color:#f4f4f5",
      "font:12px/1.4 system-ui,-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif",
      "padding:10px",
    ].join(";");

    const header = document.createElement("div");
    header.textContent = "Model downloads";
    header.style.cssText = "font-weight:650;margin-bottom:8px";
    panel.appendChild(header);

    list = document.createElement("div");
    list.style.cssText = "display:flex;flex-direction:column;gap:8px";
    panel.appendChild(list);

    document.body.appendChild(panel);
  }

  function renderDownloads() {
    ensurePanel();
    list.replaceChildren();

    for (const item of downloads.values()) {
      const row = document.createElement("div");
      row.style.cssText = "display:flex;flex-direction:column;gap:5px";

      const title = document.createElement("div");
      title.textContent = item.filename;
      title.title = item.path || item.directory || item.filename;
      title.style.cssText = "overflow:hidden;text-overflow:ellipsis;white-space:nowrap";
      row.appendChild(title);

      const progress = document.createElement("div");
      progress.style.cssText = "height:6px;overflow:hidden;border-radius:999px;background:rgba(255,255,255,0.14)";
      const bar = document.createElement("div");
      const percent = typeof item.progress === "number" ? Math.max(0, Math.min(100, item.progress * 100)) : 0;
      bar.style.cssText = `height:100%;width:${percent}%;background:#7dd3fc;transition:width 300ms ease`;
      if (item.status === "completed") bar.style.background = "#86efac";
      if (item.status === "error") bar.style.background = "#fca5a5";
      progress.appendChild(bar);
      row.appendChild(progress);

      const meta = document.createElement("div");
      const total = item.total_bytes ? ` / ${formatBytes(item.total_bytes)}` : "";
      const pct = typeof item.progress === "number" ? ` ${Math.round(item.progress * 100)}%` : "";
      meta.textContent = item.status === "error"
        ? `Error: ${item.error || "download failed"}`
        : `${item.status}${pct} · ${formatBytes(item.received_bytes || 0)}${total}`;
      meta.style.cssText = "color:rgba(244,244,245,0.72);font-size:11px";
      row.appendChild(meta);

      list.appendChild(row);
    }

    const active = Array.from(downloads.values()).some((item) =>
      ["queued", "downloading"].includes(item.status)
    );
    if (!active) {
      window.setTimeout(() => {
        const stillActive = Array.from(downloads.values()).some((item) =>
          ["queued", "downloading"].includes(item.status)
        );
        if (!stillActive && panel) {
          panel.remove();
          panel = null;
          list = null;
          downloads.clear();
        }
      }, 8000);
    }
  }

  async function pollDownload(id) {
    while (downloads.has(id)) {
      const response = await fetch(`/runpod-model-downloader/status/${id}`);
      if (!response.ok) throw new Error(`status polling failed: ${response.status}`);
      const payload = await response.json();
      downloads.set(id, payload);
      renderDownloads();
      if (payload.status === "completed" || payload.status === "error") return payload;
      await new Promise((resolve) => window.setTimeout(resolve, 1000));
    }
  }

  async function downloadModel(url, filename, directory) {
    const response = await fetch("/runpod-model-downloader/download", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ url, filename, directory }),
    });

    let payload = {};
    try {
      payload = await response.json();
    } catch {
      // Keep the original error path below.
    }

    if (!response.ok || payload.ok === false) {
      const detail = payload.error ? `: ${payload.error}` : "";
      throw new Error(`RunPod model download failed${detail}`);
    }

    if (payload.id) {
      downloads.set(payload.id, payload);
      renderDownloads();
      void pollDownload(payload.id).catch((error) => {
        const current = downloads.get(payload.id) || payload;
        downloads.set(payload.id, { ...current, status: "error", error: String(error) });
        renderDownloads();
      });
    }

    console.info(
      `[runpod-model-downloader] ${payload.status || "started"}: ${filename} -> ${payload.path || directory}`
    );
  }

  window.__comfyDesktop2 = {
    isRemote: function () {
      return false;
    },
    downloadModel,
  };
})();
