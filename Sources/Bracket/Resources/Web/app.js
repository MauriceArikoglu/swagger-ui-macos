"use strict";

(() => {
  const empty = document.getElementById("empty");
  const loading = document.getElementById("loading");
  const error = document.getElementById("error");
  const dropTarget = document.getElementById("drop-target");
  const parameters = new URLSearchParams(location.search);
  const definition = parameters.get("document");
  const filename = parameters.get("name") || "API definition";
  let dragDepth = 0;
  let completed = false;

  window.bracket = {
    state: { status: "empty", title: "", operations: 0, errors: [] },
    showDropTarget(visible) { dropTarget.hidden = !visible; }
  };

  function nativeMessage(action) {
    window.webkit?.messageHandlers?.bracket?.postMessage({ action });
  }

  document.getElementById("choose").addEventListener("click", () => nativeMessage("open"));
  // WebKit may dispatch file drags to its internal content view. The native
  // fallback reads the drag pasteboard, so the original file URL is preserved.
  document.addEventListener("dragenter", event => {
    if (!event.dataTransfer?.types.includes("Files")) return;
    event.preventDefault();
    dragDepth += 1;
    window.bracket.showDropTarget(true);
  });
  document.addEventListener("dragover", event => {
    if (event.dataTransfer?.types.includes("Files")) { event.preventDefault(); event.dataTransfer.dropEffect = "copy"; }
  });
  document.addEventListener("dragleave", () => {
    dragDepth = Math.max(0, dragDepth - 1);
    if (!dragDepth) window.bracket.showDropTarget(false);
  });
  document.addEventListener("drop", event => {
    event.preventDefault();
    dragDepth = 0;
    window.bracket.showDropTarget(false);
    if (event.dataTransfer?.files.length) nativeMessage("drop");
  });
  window.addEventListener("blur", () => { dragDepth = 0; window.bracket.showDropTarget(false); });

  if (!definition) return;
  empty.hidden = true;
  loading.hidden = false;
  document.getElementById("file-bar").hidden = false;
  document.getElementById("file-name").textContent = filename;
  document.getElementById("file-format").textContent = filename.split(".").pop().toUpperCase();
  window.bracket.state.status = "loading";

  function updateState() {
    if (!window.ui) return;
    const system = window.ui.getSystem();
    const spec = system.specSelectors.specJson().toJS();
    const errors = system.errSelectors.allErrors().toJS().filter(item => item.level === "error");
    const methods = ["get", "put", "post", "delete", "options", "head", "patch", "trace", "query"];
    const operations = Object.values(spec.paths || {}).reduce((total, item) => total + Object.keys(item || {}).filter(method => methods.includes(method)).length, 0);
    const valid = spec.swagger === "2.0" || /^3\.\d+\.\d+(?:[-+].*)?$/.test(spec.openapi || "");
    if (!valid && !errors.length && !completed) return;
    const status = valid ? "ready" : "error";
    window.bracket.state = { status, title: spec.info?.title || "", operations, errors, version: spec.openapi || spec.swagger || "" };
    loading.hidden = true;
    error.hidden = valid;
    if (!valid) {
      const parserError = errors.find(item => item.source === "parser");
      error.textContent = parserError
        ? `Syntax error${parserError.line ? ` on line ${parserError.line}` : ""}: ${parserError.message}. Correct the file, then reload with ⌘R.`
        : "Cannot read this API definition. Check its swagger or openapi version field, then reload with ⌘R.";
    }
  }

  try {
    const url = new URL(definition, location.href);
    if (url.origin !== location.origin || !url.pathname.startsWith(new URL("documents/", location.href).pathname)) throw new Error("The definition URL must be local.");
    window.ui = SwaggerUIBundle({
      url: url.href,
      dom_id: "#swagger-ui",
      presets: [SwaggerUIBundle.presets.apis],
      layout: "BaseLayout",
      deepLinking: true,
      filter: true,
      docExpansion: "list",
      defaultModelsExpandDepth: 0,
      displayRequestDuration: true,
      validatorUrl: null,
      persistAuthorization: false,
      queryConfigEnabled: false,
      oauth2RedirectUrl: new URL("vendor/oauth2-redirect.html", location.href).href,
      onComplete: () => { completed = true; requestAnimationFrame(updateState); }
    });
    let queued = false;
    new MutationObserver(() => {
      if (queued) return;
      queued = true;
      requestAnimationFrame(() => { queued = false; updateState(); });
    }).observe(document.getElementById("swagger-ui"), { childList: true, subtree: true });
  } catch (failure) {
    loading.hidden = true;
    error.hidden = false;
    error.textContent = `The viewer could not start. Reload the file with ⌘R. ${failure.message}`;
    window.bracket.state = { status: "error", title: "", operations: 0, errors: [{ message: failure.message }] };
  }
})();
