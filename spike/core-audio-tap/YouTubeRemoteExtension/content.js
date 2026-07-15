(() => {
  const runtimeApi = globalThis.browser ?? globalThis.chrome;
  const rootId = "hazakura-amp-floating-bar";
  const storageDefaults = {
    hazakuraAmpCollapsed: false,
    hazakuraAmpRepeatEnabled: false,
    hazakuraAmpPosition: null,
    hazakuraAmpPlaybackRate: 1
  };
  const boostPresets = [100, 150, 200, 300, 400];
  const playbackRates = [0.75, 1, 1.25, 1.5, 2];
  const staleStateThresholdMs = 5_000;
  const statePollIntervalMs = 3_000;

  let root;
  let header;
  let boostInput;
  let boostValue;
  let boostSafetyText;
  let statusText;
  let repeatButton;
  let captionsButton;
  let collapseButton;
  let presetButtons = [];
  let speedButtons = [];
  let repeatEnabled = false;
  let collapsed = false;
  let playbackRate = 1;
  let savedPosition = null;
  let dragState = null;
  let lastUrl = location.href;
  let sendTimer;
  let boundVideo = null;
  let endedListener = null;

  function isWatchPage() {
    return location.hostname.endsWith("youtube.com") && location.pathname === "/watch";
  }

  function runtimeSend(payload) {
    if (!runtimeApi?.runtime?.sendMessage) {
      return Promise.resolve({ ok: false, error: "Extension runtime unavailable" });
    }

    const message = { target: "hazakuraAmp", payload };
    const response = runtimeApi.runtime.sendMessage(message);
    if (response && typeof response.then === "function") {
      return response;
    }

    return new Promise((resolve) => {
      runtimeApi.runtime.sendMessage(message, resolve);
    });
  }

  function storageGet(defaults) {
    if (!runtimeApi?.storage?.local) {
      return Promise.resolve(defaults);
    }
    const response = runtimeApi.storage.local.get(defaults);
    if (response && typeof response.then === "function") {
      return response;
    }
    return new Promise((resolve) => runtimeApi.storage.local.get(defaults, resolve));
  }

  function storageSet(values) {
    if (!runtimeApi?.storage?.local) {
      return;
    }
    runtimeApi.storage.local.set(values);
  }

  function isPosition(value) {
    return value
      && typeof value.x === "number"
      && typeof value.y === "number"
      && Number.isFinite(value.x)
      && Number.isFinite(value.y);
  }

  function clampPosition(position) {
    if (!root) {
      return position;
    }
    const margin = 12;
    const width = root.offsetWidth || 286;
    const height = root.offsetHeight || 120;
    const maxX = Math.max(margin, window.innerWidth - width - margin);
    const maxY = Math.max(margin, window.innerHeight - height - margin);
    return {
      x: Math.min(Math.max(position.x, margin), maxX),
      y: Math.min(Math.max(position.y, margin), maxY)
    };
  }

  function applyPosition(position, persist = false) {
    if (!root || !isPosition(position)) {
      return;
    }

    savedPosition = clampPosition(position);
    root.style.left = `${Math.round(savedPosition.x)}px`;
    root.style.top = `${Math.round(savedPosition.y)}px`;
    root.style.right = "auto";
    root.style.bottom = "auto";

    if (persist) {
      storageSet({ hazakuraAmpPosition: savedPosition });
    }
  }

  function setStatus(message) {
    if (statusText) {
      statusText.textContent = message;
    }
  }

  function formatStatusLabel(state, isConnected) {
    if (!isConnected) {
      return "アプリ未接続";
    }
    if (state?.isRunning) {
      return "動作中";
    }

    const raw = String(state?.statusText || "").trim().toLowerCase();
    switch (raw) {
      case "running":
        return "動作中";
      case "sleeping":
        return "スリープ中";
      case "waking":
        return "復帰中";
      case "reconnecting output":
        return "再接続中";
      case "manual start required":
        return "開始が必要";
      case "restart required":
        return "再開が必要";
      case "permission denied":
        return "権限が必要";
      case "error":
        return "エラー";
      case "stopped":
      case "idle":
      case "":
        return "停止中";
      default:
        return "停止中";
    }
  }

  function setBoostPercent(percent) {
    const clamped = Math.max(0, Math.min(400, Number(percent) || 0));
    boostInput.value = String(clamped);
    boostValue.textContent = `${Math.round(clamped)}%`;
    updateBoostSafety(clamped);
    presetButtons.forEach((button) => {
      const preset = Number(button.dataset.boostPreset);
      button.classList.toggle("is-active", preset === Math.round(clamped));
      button.setAttribute("aria-pressed", String(preset === Math.round(clamped)));
    });
    return clamped;
  }

  function updateBoostSafety(percent) {
    if (!root || !boostSafetyText) {
      return;
    }
    const isHighBoost = percent >= 300;
    root.classList.toggle("hazakura-amp-high-boost", isHighBoost);
    boostSafetyText.textContent = isHighBoost ? "300%以上は音割れしやすいです" : "";
  }

  function stateUpdatedAtMs(state) {
    if (typeof state?.updatedAt !== "number" || !Number.isFinite(state.updatedAt)) {
      return null;
    }
    return state.updatedAt * 1000;
  }

  function isFreshState(state) {
    const updatedAt = stateUpdatedAtMs(state);
    return updatedAt !== null && Date.now() - updatedAt <= staleStateThresholdMs;
  }

  function markConnection(isConnected, message) {
    if (!root) {
      return;
    }
    root.classList.toggle("hazakura-amp-disconnected", !isConnected);
    if (!isConnected) {
      setStatus(message || "アプリ未接続");
    }
  }

  function applyRemoteState(state) {
    if (!state || !root || !boostInput) {
      return;
    }
    if (typeof state.configuredGain === "number") {
      setBoostPercent(state.configuredGain * 100);
    }
    if (!isFreshState(state)) {
      markConnection(false, "アプリ未接続");
      return;
    }
    markConnection(true);
    setStatus(formatStatusLabel(state, true));
  }

  function applyCollapsed() {
    root.classList.toggle("hazakura-amp-collapsed", collapsed);
    collapseButton.setAttribute("aria-expanded", String(!collapsed));
    collapseButton.textContent = collapsed ? "+" : "−";
    requestAnimationFrame(() => {
      if (isPosition(savedPosition)) {
        applyPosition(savedPosition, true);
      }
    });
  }

  function currentVideo() {
    return document.querySelector("video.html5-main-video") || document.querySelector("video");
  }

  function applyRepeat() {
    const video = currentVideo();
    if (video) {
      video.loop = repeatEnabled;
    }
    if (repeatButton) {
      repeatButton.setAttribute("aria-pressed", String(repeatEnabled));
      repeatButton.classList.toggle("is-on", repeatEnabled);
    }
    bindVideoLifecycle(video);
  }

  function applyPlaybackRate() {
    const video = currentVideo();
    if (video) {
      video.playbackRate = playbackRate;
    }
    speedButtons.forEach((button) => {
      const rate = Number(button.dataset.playbackRate);
      const isActive = Math.abs(rate - playbackRate) < 0.001;
      button.classList.toggle("is-active", isActive);
      button.setAttribute("aria-pressed", String(isActive));
    });
    bindVideoLifecycle(video);
  }

  function setPlaybackRate(rate) {
    const numeric = Number(rate);
    if (!Number.isFinite(numeric)) {
      return;
    }
    playbackRate = Math.max(0.75, Math.min(2, numeric));
    storageSet({ hazakuraAmpPlaybackRate: playbackRate });
    applyPlaybackRate();
  }

  function toggleCaptions() {
    // Prefer the native YouTube CC control rather than inventing captions.
    const selectors = [
      "button.ytp-subtitles-button",
      ".ytp-subtitles-button",
      "button[aria-label*='字幕']",
      "button[aria-label*='Subtitles']",
      "button[aria-label*='Captions']",
      "button[data-tooltip-target-id='ytp-subtitles-button']"
    ];
    for (const selector of selectors) {
      const button = document.querySelector(selector);
      if (button) {
        button.click();
        setStatus("字幕を切替");
        return;
      }
    }
    setStatus("字幕ボタンなし");
  }

  function onVideoEnded() {
    // Return system boost to neutral when the current video ends.
    // Skip when page-local repeat keeps the same video looping.
    // Do not requestStart: ending a video must not launch the mute/capture path.
    if (repeatEnabled) {
      return;
    }
    sendGainPercentOnly(100);
    setStatus("動画終了→100%");
  }

  function bindVideoLifecycle(video) {
    if (boundVideo === video) {
      return;
    }
    if (boundVideo && endedListener) {
      boundVideo.removeEventListener("ended", endedListener);
    }
    boundVideo = video || null;
    endedListener = null;
    if (!boundVideo) {
      return;
    }
    endedListener = onVideoEnded;
    boundVideo.addEventListener("ended", endedListener);
    boundVideo.playbackRate = playbackRate;
    boundVideo.loop = repeatEnabled;
  }

  function sendCommand(command) {
    return runtimeSend(command).then((response) => {
      if (!response?.ok) {
        markConnection(false, "アプリ未接続");
        return null;
      }
      return response.reply;
    }).catch(() => {
      markConnection(false, "アプリ未接続");
      return null;
    });
  }

  function requestState() {
    return sendCommand({ kind: "requestState" }).then((state) => {
      applyRemoteState(state);
    });
  }

  function sendGainPercent(percent) {
    const clamped = setBoostPercent(percent);
    const gain = clamped / 100;
    clearTimeout(sendTimer);
    sendTimer = setTimeout(() => {
      sendCommand({ kind: "setGain", gain })
        .then(() => sendCommand({ kind: "requestStart" }))
        .then((state) => applyRemoteState(state))
        .then(() => requestState());
    }, 120);
  }

  // User-independent safety path: update gain only, never auto-start the pipeline.
  function sendGainPercentOnly(percent) {
    const clamped = setBoostPercent(percent);
    const gain = clamped / 100;
    clearTimeout(sendTimer);
    sendTimer = setTimeout(() => {
      sendCommand({ kind: "setGain", gain })
        .then((state) => applyRemoteState(state))
        .then(() => requestState());
    }, 80);
  }

  function sendGainFromInput() {
    sendGainPercent(boostInput.value);
  }

  function makeButton(label, className) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = className;
    button.textContent = label;
    return button;
  }

  function startDrag(event) {
    if (event.button !== 0 || event.target === collapseButton) {
      return;
    }

    const rect = root.getBoundingClientRect();
    dragState = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      rootX: rect.left,
      rootY: rect.top
    };
    root.classList.add("hazakura-amp-dragging");
    header.setPointerCapture(event.pointerId);
    event.preventDefault();
  }

  function moveDrag(event) {
    if (!dragState || event.pointerId !== dragState.pointerId) {
      return;
    }
    applyPosition({
      x: dragState.rootX + event.clientX - dragState.startX,
      y: dragState.rootY + event.clientY - dragState.startY
    });
  }

  function endDrag(event) {
    if (!dragState || event.pointerId !== dragState.pointerId) {
      return;
    }
    if (header.hasPointerCapture?.(event.pointerId)) {
      header.releasePointerCapture(event.pointerId);
    }
    root.classList.remove("hazakura-amp-dragging");
    if (isPosition(savedPosition)) {
      storageSet({ hazakuraAmpPosition: savedPosition });
    }
    dragState = null;
  }

  function createBar() {
    root = document.createElement("section");
    root.id = rootId;
    root.className = "hazakura-amp-floating-bar";
    root.setAttribute("aria-label", "Hazakura Amp YouTube remote");

    header = document.createElement("div");
    header.className = "hazakura-amp-header";
    header.addEventListener("pointerdown", startDrag);
    header.addEventListener("pointermove", moveDrag);
    header.addEventListener("pointerup", endDrag);
    header.addEventListener("pointercancel", endDrag);

    const title = document.createElement("span");
    title.className = "hazakura-amp-title";
    title.textContent = "Hazakura Amp";

    collapseButton = makeButton("−", "hazakura-amp-icon-button");
    collapseButton.setAttribute("aria-label", "Collapse Hazakura Amp remote");
    collapseButton.addEventListener("click", () => {
      collapsed = !collapsed;
      storageSet({ hazakuraAmpCollapsed: collapsed });
      applyCollapsed();
    });

    header.append(title, collapseButton);

    const controls = document.createElement("div");
    controls.className = "hazakura-amp-controls";

    const boostRow = document.createElement("label");
    boostRow.className = "hazakura-amp-boost-row";

    const boostLabel = document.createElement("span");
    boostLabel.textContent = "Boost";

    boostInput = document.createElement("input");
    boostInput.type = "range";
    boostInput.min = "0";
    boostInput.max = "400";
    boostInput.step = "5";
    boostInput.value = "100";
    boostInput.setAttribute("aria-label", "Hazakura Amp boost");
    boostInput.addEventListener("input", sendGainFromInput);

    boostValue = document.createElement("output");
    boostValue.className = "hazakura-amp-boost-value";
    boostValue.textContent = "100%";

    boostRow.append(boostLabel, boostInput, boostValue);

    const presetRow = document.createElement("div");
    presetRow.className = "hazakura-amp-preset-row";
    presetButtons = boostPresets.map((preset) => {
      const button = makeButton(String(preset), "hazakura-amp-preset-button");
      button.dataset.boostPreset = String(preset);
      button.setAttribute("aria-label", `Set Hazakura Amp boost to ${preset}%`);
      button.setAttribute("aria-pressed", "false");
      button.addEventListener("click", () => sendGainPercent(preset));
      return button;
    });
    presetRow.append(...presetButtons);

    const speedRow = document.createElement("div");
    speedRow.className = "hazakura-amp-speed-row";
    const speedLabel = document.createElement("span");
    speedLabel.className = "hazakura-amp-row-label";
    speedLabel.textContent = "速度";
    const speedButtonsWrap = document.createElement("div");
    speedButtonsWrap.className = "hazakura-amp-speed-buttons";
    speedButtons = playbackRates.map((rate) => {
      const label = rate === 1 ? "1x" : `${rate}x`;
      const button = makeButton(label, "hazakura-amp-speed-button");
      button.dataset.playbackRate = String(rate);
      button.setAttribute("aria-label", `Set playback speed to ${rate}`);
      button.setAttribute("aria-pressed", "false");
      button.addEventListener("click", () => setPlaybackRate(rate));
      return button;
    });
    speedButtonsWrap.append(...speedButtons);
    speedRow.append(speedLabel, speedButtonsWrap);

    boostSafetyText = document.createElement("div");
    boostSafetyText.className = "hazakura-amp-safety";
    boostSafetyText.setAttribute("aria-live", "polite");

    const actionRow = document.createElement("div");
    actionRow.className = "hazakura-amp-action-row";

    const tools = document.createElement("div");
    tools.className = "hazakura-amp-tools";

    repeatButton = makeButton("Repeat", "hazakura-amp-repeat-button");
    repeatButton.setAttribute("aria-pressed", "false");
    repeatButton.addEventListener("click", () => {
      repeatEnabled = !repeatEnabled;
      storageSet({ hazakuraAmpRepeatEnabled: repeatEnabled });
      applyRepeat();
    });

    captionsButton = makeButton("字幕", "hazakura-amp-captions-button");
    captionsButton.setAttribute("aria-label", "Toggle YouTube captions");
    captionsButton.addEventListener("click", toggleCaptions);

    tools.append(repeatButton, captionsButton);

    statusText = document.createElement("span");
    statusText.className = "hazakura-amp-status";
    statusText.textContent = "停止中";

    actionRow.append(tools, statusText);
    controls.append(boostRow, presetRow, speedRow, boostSafetyText, actionRow);
    root.append(header, controls);
    document.documentElement.append(root);
  }

  function ensureBar() {
    if (!isWatchPage()) {
      root?.remove();
      root = undefined;
      return;
    }

    if (!document.getElementById(rootId)) {
      createBar();
      if (isPosition(savedPosition)) {
        requestAnimationFrame(() => applyPosition(savedPosition));
      }
      applyCollapsed();
      applyRepeat();
      applyPlaybackRate();
      requestState();
    } else {
      applyRepeat();
      applyPlaybackRate();
    }
  }

  function handleNavigation() {
    if (location.href === lastUrl) {
      return;
    }
    lastUrl = location.href;
    setTimeout(() => {
      ensureBar();
      applyRepeat();
      applyPlaybackRate();
      requestState();
    }, 200);
  }

  storageGet(storageDefaults).then((values) => {
    collapsed = Boolean(values.hazakuraAmpCollapsed);
    repeatEnabled = Boolean(values.hazakuraAmpRepeatEnabled);
    const storedRate = Number(values.hazakuraAmpPlaybackRate);
    playbackRate = playbackRates.includes(storedRate) ? storedRate : 1;
    savedPosition = isPosition(values.hazakuraAmpPosition) ? values.hazakuraAmpPosition : null;
    ensureBar();
  });

  document.addEventListener("yt-navigate-finish", handleNavigation);
  document.addEventListener("loadedmetadata", () => {
    applyRepeat();
    applyPlaybackRate();
  }, true);
  window.addEventListener("resize", () => {
    if (isPosition(savedPosition)) {
      applyPosition(savedPosition, true);
    }
  });
  setInterval(handleNavigation, 1000);
  setInterval(() => {
    if (root && isWatchPage()) {
      applyPlaybackRate();
      applyRepeat();
      requestState();
    }
  }, statePollIntervalMs);
})();
