(function () {
  "use strict";

  if (window.__runpodModelDownloaderInstalled) return;
  window.__runpodModelDownloaderInstalled = true;

  if (window.__comfyDesktop2 && typeof window.__comfyDesktop2.downloadModel === "function") {
    return;
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
