(function () {
  var editor = null;
  var config = window.monacoConfig || {};
  var pendingValue = typeof config.initialValue === "string" ? config.initialValue : "";
  var pendingOptions = config.options || {};
  var pendingLanguage = config.language || "plaintext";
  var pendingTheme = config.theme || "vs";
  var pendingBreakpoints = [];
  var breakpointDecorations = [];
  var lspClient = null;
  var lspReady = false;
  var lspWebSocketURL = config.lspWebSocketURL || "ws://127.0.0.1:6009";
  var lspWorkspaceRoot = config.lspWorkspaceRoot || null;
  var documentPath = config.documentPath || null;
  var lspClientScriptURL = config.lspClientScriptURL || null;
  var monacoWorkerURLs = config.monacoWorkerURLs || null;
  var lspInitPatched = false;
  var lspSyncForced = false;
  var lspSyncPatched = false;
  var gdscriptRegistered = false;
  var gdshaderRegistered = false;
  var debugLoggingEnabled = !!config.debugLoggingEnabled;
  var contextMenuActionMap = Object.create(null);
  var diagnosticsListenerInstalled = false;
  var lastDiagnosticsFingerprint = null;

  function postMessage(handlerName, payload) {
    try {
      if (
        window.webkit &&
        window.webkit.messageHandlers &&
        window.webkit.messageHandlers[handlerName]
      ) {
        window.webkit.messageHandlers[handlerName].postMessage(payload);
      }
    } catch (e) {}
  }

  function monacoLog(level, message) {
    if (!debugLoggingEnabled) {
      return;
    }
    postMessage("monacoLog", { level: level, message: message });
  }
  window.monacoLog = monacoLog;

  function loadScript(src, onLoad, onError) {
    var script = document.createElement("script");
    script.src = src;
    script.async = true;
    if (debugLoggingEnabled) {
      script.addEventListener("error", function () {
        monacoLog("error", "Script load error: " + src);
      });
      script.addEventListener("load", function () {
        monacoLog("info", "Script loaded: " + src);
      });
    }
    script.onload = function () {
      if (onLoad) {
        onLoad();
      }
    };
    script.onerror = function () {
      if (onError) {
        onError();
      }
    };
    document.head.appendChild(script);
  }

  function ensureMonacoEnvironment(force) {
    if (!force && window.MonacoEnvironment && window.MonacoEnvironment.getWorker) {
      return;
    }
    if (!monacoWorkerURLs || Object.keys(monacoWorkerURLs).length === 0) {
      if (force) {
        monacoLog("warn", "Monaco worker map missing; keeping existing environment.");
      }
      return;
    }
    function normalizeWorkerLabel(label, moduleId) {
      var value = (label || moduleId || "").toLowerCase();
      if (value.indexOf("json") >= 0) return "json";
      if (value.indexOf("css") >= 0) return "css";
      if (value.indexOf("html") >= 0) return "html";
      if (value.indexOf("typescript") >= 0 || value.indexOf("javascript") >= 0) {
        return "typescript";
      }
      return "editor";
    }

    function resolveWorkerURL(label, moduleId) {
      if (!monacoWorkerURLs) {
        return null;
      }
      var key = normalizeWorkerLabel(label, moduleId);
      return monacoWorkerURLs[key] || monacoWorkerURLs.editor || null;
    }

    if (debugLoggingEnabled) {
      monacoLog(
        "info",
        "Monaco worker map=" + JSON.stringify(monacoWorkerURLs || {})
      );
    }

    window.MonacoEnvironment = {
      getWorker: function (moduleId, label) {
        var workerSourceURL = resolveWorkerURL(label, moduleId);
        if (!workerSourceURL) {
          throw new Error(
            "Missing Monaco worker URL for label=" +
              label +
              " moduleId=" +
              moduleId
          );
        }
        if (debugLoggingEnabled) {
          monacoLog(
            "info",
            "Monaco getWorker label=" + label + " moduleId=" + moduleId
          );
        }
        var source =
          "self.addEventListener('error', function(e){try{self.postMessage({__monacoWorkerError:true,message:e.message,filename:e.filename,lineno:e.lineno,colno:e.colno});}catch(_){};});" +
          "self.addEventListener('unhandledrejection', function(e){try{self.postMessage({__monacoWorkerRejection:true,reason:(e&&e.reason&&e.reason.message)?e.reason.message:String(e.reason)});}catch(_){};});" +
          "try{importScripts('" +
          workerSourceURL +
          "');}catch(e){try{self.postMessage({__monacoWorkerError:true,message:e.message,stack:e.stack});}catch(_){};throw e;}";
        var blob = new Blob([source], { type: "text/javascript" });
        var workerUrl = URL.createObjectURL(blob);
        var worker = new Worker(workerUrl);
        if (debugLoggingEnabled) {
          monacoLog(
            "info",
            "Monaco worker created label=" +
              label +
              " moduleId=" +
              moduleId +
              " source=" +
              workerSourceURL
          );
        }
        worker.addEventListener("message", function (e) {
          if (e && e.data && e.data.__monacoWorkerError) {
            monacoLog(
              "error",
              "Worker error (" +
                label +
                "): " +
                e.data.message +
                (e.data.filename
                  ? " at " +
                    e.data.filename +
                    ":" +
                    e.data.lineno +
                    ":" +
                    e.data.colno
                  : "") +
                (e.data.stack ? " stack=" + e.data.stack : "")
            );
          } else if (e && e.data && e.data.__monacoWorkerRejection) {
            monacoLog(
              "error",
              "Worker unhandled rejection (" +
                label +
                "): " +
                e.data.reason
            );
          }
        });
        worker.onerror = function (e) {
          monacoLog(
            "error",
            "Worker error (" +
              label +
              "): " +
              e.message +
              " at " +
              e.filename +
              ":" +
              e.lineno +
              ":" +
              e.colno
          );
        };
        return worker;
      },
      getWorkerUrl: function (moduleId, label) {
        var workerSourceURL = resolveWorkerURL(label, moduleId);
        if (debugLoggingEnabled) {
          monacoLog(
            "info",
            "Monaco getWorkerUrl label=" +
              label +
              " moduleId=" +
              moduleId +
              " url=" +
              workerSourceURL
          );
        }
        return workerSourceURL;
      },
    };
    if (force && debugLoggingEnabled) {
      monacoLog("info", "MonacoEnvironment overridden for worker URLs.");
    }
  }

  function startLspClient() {
    if (lspReady || !window.MonacoLspClient) {
      return;
    }
    try {
      if (typeof window.__startMonacoLspClient === "function") {
        var result = window.__startMonacoLspClient(window.MonacoLspClient);
        if (result && typeof result.then === "function") {
          result
            .then(function (client) {
              lspClient = client || lspClient;
              lspReady = true;
              forceStartTextSync(lspClient);
              enableFullTextSyncIfNeeded(lspClient);
              ensureEditorModel();
              logModelState("LSP ready:");
            })
            .catch(function (e) {
              lspReady = false;
              monacoLog("error", "Failed to start Monaco LSP client: " + e);
            });
        } else {
          lspClient = result;
          lspReady = true;
          forceStartTextSync(lspClient);
          enableFullTextSyncIfNeeded(lspClient);
          ensureEditorModel();
          logModelState("LSP ready:");
        }
      } else {
        monacoLog("info", "Monaco LSP client loaded (no start callback)");
        lspReady = true;
      }
    } catch (e) {
      lspReady = false;
      monacoLog("error", "Failed to start Monaco LSP client: " + e);
    }
  }

  function toFileUri(path) {
    if (!path) {
      return null;
    }
    if (path.indexOf("file://") === 0) {
      return path;
    }
    if (path[0] !== "/") {
      return null;
    }
    return "file://" + encodeURI(path);
  }

  function joinPath(base, rel) {
    if (!base) {
      return null;
    }
    var cleanBase = base.replace(/\/+$/, "");
    var cleanRel = (rel || "").replace(/^\/+/, "");
    if (!cleanRel) {
      return cleanBase;
    }
    return cleanBase + "/" + cleanRel;
  }

  function resolveDocumentUri() {
    if (documentPath && documentPath.indexOf("file://") === 0) {
      return documentPath;
    }
    if (documentPath && documentPath[0] === "/") {
      return toFileUri(documentPath);
    }
    if (lspWorkspaceRoot && documentPath) {
      return toFileUri(joinPath(lspWorkspaceRoot, documentPath));
    }
    return null;
  }

  function basename(path) {
    if (!path) {
      return "";
    }
    var clean = path.replace(/\/+$/, "");
    var parts = clean.split("/");
    return parts.length ? parts[parts.length - 1] : clean;
  }

  function ensureEditorModel() {
    if (!editor) {
      return;
    }
    var desiredUri = resolveDocumentUri();
    var currentModel = editor.getModel();
    var value = currentModel ? currentModel.getValue() : pendingValue || "";
    if (desiredUri) {
      var targetUri = monaco.Uri.parse(desiredUri);
      if (!currentModel || currentModel.uri.toString() !== targetUri.toString()) {
        var newModel = monaco.editor.createModel(value, pendingLanguage || "plaintext", targetUri);
        if (currentModel) {
          currentModel.dispose();
        }
        editor.setModel(newModel);
      }
    }
    if (editor.getModel() && pendingLanguage) {
      monaco.editor.setModelLanguage(editor.getModel(), pendingLanguage);
    }
  }

  function logModelState(prefix) {
    if (!editor || !debugLoggingEnabled) {
      return;
    }
    var model = editor.getModel();
    if (!model) {
      monacoLog("info", prefix + " model=nil");
      return;
    }
    monacoLog(
      "info",
      prefix +
        " uri=" +
        model.uri.toString() +
        " language=" +
        model.getLanguageId()
    );
  }

  function diagnosticsSeverityLabel(severity) {
    switch (severity) {
      case 8:
        return "error";
      case 4:
        return "warning";
      case 2:
        return "info";
      case 1:
        return "hint";
      default:
        return "unknown";
    }
  }

  function logModelDiagnostics(model, reason) {
    if (!debugLoggingEnabled || !model || !monaco || !monaco.editor) {
      return;
    }
    var markers = monaco.editor.getModelMarkers({ resource: model.uri }) || [];
    var fingerprint = markers
      .map(function (marker) {
        return [
          marker.severity,
          marker.startLineNumber,
          marker.startColumn,
          marker.endLineNumber,
          marker.endColumn,
          marker.message,
          marker.source,
          marker.code,
          marker.owner,
        ]
          .filter(function (entry) {
            return entry !== undefined && entry !== null;
          })
          .join("|");
      })
      .join("::");
    if (fingerprint === lastDiagnosticsFingerprint) {
      return;
    }
    lastDiagnosticsFingerprint = fingerprint;
    monacoLog(
      "info",
      "Diagnostics (" +
        reason +
        ") count=" +
        markers.length +
        " uri=" +
        model.uri.toString()
    );
    markers.forEach(function (marker) {
      monacoLog(
        "info",
        [
          diagnosticsSeverityLabel(marker.severity),
          "L" + marker.startLineNumber + ":" + marker.startColumn,
          marker.message,
          marker.source ? "source=" + marker.source : null,
          marker.code ? "code=" + marker.code : null,
          marker.owner ? "owner=" + marker.owner : null,
        ]
          .filter(function (entry) {
            return entry;
          })
          .join(" | ")
      );
    });
  }

  function installDiagnosticsLogging() {
    if (diagnosticsListenerInstalled || !monaco || !monaco.editor) {
      return;
    }
    diagnosticsListenerInstalled = true;
    monaco.editor.onDidChangeMarkers(function (uris) {
      if (!editor) {
        return;
      }
      var model = editor.getModel();
      if (!model) {
        return;
      }
      if (
        Array.isArray(uris) &&
        !uris.some(function (uri) {
          return uri.toString() === model.uri.toString();
        })
      ) {
        return;
      }
      logModelDiagnostics(model, "markersChanged");
    });
  }

  function forceStartTextSync(lspClient) {
    if (lspSyncForced || !lspClient) {
      return;
    }
    var bridge = lspClient._bridge || lspClient.bridge;
    if (!bridge || bridge._started === undefined) {
      return;
    }
    lspSyncForced = true;
    var startSync = function () {
      if (!bridge) {
        return;
      }
      if (!bridge._started) {
        bridge._started = true;
        monaco.editor.onDidCreateModel(function (m) {
          if (typeof bridge._getOrCreateManagedModel === "function") {
            try {
              bridge._getOrCreateManagedModel(m);
            } catch (e) {}
          }
        });
      }
      monaco.editor.getModels().forEach(function (m) {
        if (typeof bridge._getOrCreateManagedModel === "function") {
          try {
            bridge._getOrCreateManagedModel(m);
          } catch (e) {}
        }
      });
    };

    var initPromise = lspClient._initPromise;
    if (initPromise && typeof initPromise.then === "function") {
      initPromise.then(startSync).catch(startSync);
    } else {
      startSync();
    }
  }

  function patchLspInit(lsp) {
    if (lspInitPatched || !lsp || !lsp.MonacoLspClient) {
      return;
    }
    lspInitPatched = true;
    var proto = lsp.MonacoLspClient.prototype;
    if (typeof proto._init !== "function") {
      return;
    }
    proto._init = function () {
      var rootUri = lspWorkspaceRoot ? toFileUri(lspWorkspaceRoot) : null;
      var rootPath = lspWorkspaceRoot || null;
      var workspaceFolders = rootUri
        ? [{ uri: rootUri, name: basename(lspWorkspaceRoot) }]
        : null;
      var self = this;
      return self._connection.server
        .initialize({
          processId: null,
          capabilities: self._capabilitiesRegistry.getClientCapabilities(),
          rootUri: rootUri,
          rootPath: rootPath,
          workspaceFolders: workspaceFolders,
        })
        .then(function (result) {
          self._connection.server.initialized({});
          self._capabilitiesRegistry.setServerCapabilities(result.capabilities);
          if (
            workspaceFolders &&
            self._connection.server &&
            typeof self._connection.server.workspaceDidChangeWorkspaceFolders ===
              "function"
          ) {
            try {
              self._connection.server.workspaceDidChangeWorkspaceFolders({
                event: { added: workspaceFolders, removed: [] },
              });
            } catch (e) {}
          }
        });
    };
  }

  function getSyncKindFromCapabilities(capabilities) {
    if (!capabilities || !capabilities.textDocumentSync) {
      return null;
    }
    if (typeof capabilities.textDocumentSync === "number") {
      return capabilities.textDocumentSync;
    }
    if (
      typeof capabilities.textDocumentSync === "object" &&
      capabilities.textDocumentSync &&
      typeof capabilities.textDocumentSync.change === "number"
    ) {
      return capabilities.textDocumentSync.change;
    }
    return null;
  }

  function enableFullTextSyncIfNeeded(lspClient) {
    if (lspSyncPatched || !lspClient || !lspClient._connection) {
      return;
    }
    var applyPatch = function () {
      if (lspSyncPatched || !lspClient) {
        return;
      }
      var registry = lspClient._capabilitiesRegistry;
      var caps = registry ? registry._serverCapabilities : null;
      var syncKind = getSyncKindFromCapabilities(caps);
      if (syncKind !== 1) {
        return;
      }
      var server = lspClient._connection.server;
      if (!server || server.__fullTextSyncPatched) {
        return;
      }
      var original = server.textDocumentDidChange;
      if (typeof original !== "function") {
        return;
      }
      server.textDocumentDidChange = function (params) {
        try {
          if (
            params &&
            params.textDocument &&
            typeof params.textDocument.uri === "string"
          ) {
            var targetUri = params.textDocument.uri.toLowerCase();
            var models = monaco.editor.getModels();
            for (var i = 0; i < models.length; i++) {
              var model = models[i];
              if (model.uri.toString(true).toLowerCase() === targetUri) {
                return original.call(server, {
                  textDocument: {
                    uri: params.textDocument.uri,
                    version: params.textDocument.version,
                  },
                  contentChanges: [{ text: model.getValue() }],
                });
              }
            }
          }
        } catch (e) {}
        return original.call(server, params);
      };
      server.__fullTextSyncPatched = true;
      lspSyncPatched = true;
      monacoLog("info", "LSP server requests full document sync; patched didChange.");
    };

    var initPromise = lspClient._initPromise;
    if (initPromise && typeof initPromise.then === "function") {
      initPromise.then(applyPatch).catch(applyPatch);
    } else {
      applyPatch();
    }
  }

  if (typeof window.__startMonacoLspClient !== "function") {
    window.__startMonacoLspClient = function (lsp) {
      var MonacoLspClient = lsp.MonacoLspClient;
      var WebSocketTransport = lsp.WebSocketTransport;
      patchLspInit(lsp);
      return new Promise(function (resolve, reject) {
        var socket = new WebSocket(lspWebSocketURL);
        socket.binaryType = "arraybuffer";
        socket.addEventListener("open", function () {
          try {
            var transport = new WebSocketTransport(socket);
            resolve(new MonacoLspClient(transport));
          } catch (e) {
            reject(e);
          }
        });
        socket.addEventListener("error", function (e) {
          reject(e);
        });
        socket.addEventListener("close", function () {
          if (!lspReady) {
            reject(new Error("WebSocket closed before LSP client started."));
          }
        });
      });
    };
  }

  if (debugLoggingEnabled) {
    monacoLog("info", "script loaded");
    var isLoggingError = false;
    var formatErrorDetail = function (message, source, line, col, error, extra) {
      var parts = [];
      parts.push("JS Error: " + message + " at " + source + ":" + line + ":" + col);
      if (error) {
        if (error.name || error.message) {
          parts.push("error=" + (error.name ? error.name + ": " : "") + (error.message || ""));
        }
        if (error.stack) {
          parts.push("stack=" + error.stack);
        }
      }
      if (extra) {
        parts.push(extra);
      }
      return parts.join(" ");
    };
    var originalConsoleLog = console.log;
    var originalConsoleWarn = console.warn;
    var originalConsoleError = console.error;
    console.log = function () {
      originalConsoleLog.apply(console, arguments);
      monacoLog("log", Array.from(arguments).join(" "));
    };
    console.warn = function () {
      originalConsoleWarn.apply(console, arguments);
      monacoLog("warn", Array.from(arguments).join(" "));
    };
    console.error = function () {
      originalConsoleError.apply(console, arguments);
      monacoLog("error", Array.from(arguments).join(" "));
    };
    var errorHandler = function (event, isCapture) {
      if (isLoggingError) {
        return;
      }
      isLoggingError = true;
      try {
        if (event && event.target && event.target.tagName === "SCRIPT") {
          var src = event.target.src || "(inline)";
          monacoLog("error", "Script load error: " + src);
          return;
        }
        var message = event && event.message ? event.message : "unknown error";
        var source = event && event.filename ? event.filename : "(unknown)";
        var line = event && event.lineno ? event.lineno : 0;
        var col = event && event.colno ? event.colno : 0;
        var error = event && event.error ? event.error : null;
        var targetInfo = "";
        if (event && event.target && event.target.tagName) {
          targetInfo =
            " target=" +
            event.target.tagName +
            (event.target.src ? " src=" + event.target.src : "");
        }
        var phaseInfo = isCapture ? " capture" : "";
        monacoLog(
          "error",
          formatErrorDetail(message, source, line, col, error, targetInfo + phaseInfo)
        );
      } finally {
        isLoggingError = false;
      }
    };
    window.addEventListener("error", function (event) {
      errorHandler(event, false);
    });
    window.addEventListener(
      "error",
      function (event) {
        errorHandler(event, true);
      },
      true
    );
    var previousOnError = window.onerror;
    window.onerror = function (message, source, lineno, colno, error) {
      if (!isLoggingError) {
        isLoggingError = true;
        try {
          monacoLog(
            "error",
            formatErrorDetail(
              message || "unknown error",
              source || "(unknown)",
              lineno || 0,
              colno || 0,
              error || null,
              "onerror"
            )
          );
        } finally {
          isLoggingError = false;
        }
      }
      if (typeof previousOnError === "function") {
        try {
          return previousOnError(message, source, lineno, colno, error);
        } catch (e) {}
      }
      return false;
    };
    if (typeof window.Worker === "function") {
      try {
        var OriginalWorker = window.Worker;
        var wrapWorkerScript = function (scriptURL) {
          var source =
            "self.addEventListener('error', function(e){try{self.postMessage({__wrappedWorkerError:true,message:e.message,filename:e.filename,lineno:e.lineno,colno:e.colno,stack:e.error&&e.error.stack});}catch(_){};});" +
            "self.addEventListener('unhandledrejection', function(e){try{self.postMessage({__wrappedWorkerRejection:true,reason:(e&&e.reason&&e.reason.message)?e.reason.message:String(e.reason)});}catch(_){};});" +
            "try{importScripts('" +
            scriptURL +
            "');}catch(e){try{self.postMessage({__wrappedWorkerError:true,message:e.message,stack:e.stack});}catch(_){};throw e;}";
          return URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
        };
        var WorkerWrapper = function (scriptURL, options) {
          var urlString = scriptURL ? String(scriptURL) : "";
          var useWrapper = !options || options.type !== "module";
          var workerScript = useWrapper ? wrapWorkerScript(urlString) : urlString;
          var worker = new OriginalWorker(workerScript, options);
          try {
            monacoLog(
              "info",
              "Worker created url=" + urlString + (useWrapper ? " (wrapped)" : "")
            );
          } catch (e) {}
          worker.addEventListener("error", function (e) {
            monacoLog(
              "error",
              "Worker error: " +
                (e && e.message ? e.message : "unknown") +
                " at " +
                (e && e.filename ? e.filename : "(unknown)") +
                ":" +
                (e && e.lineno ? e.lineno : 0) +
                ":" +
                (e && e.colno ? e.colno : 0)
            );
          });
          worker.addEventListener("message", function (e) {
            var data = e && e.data ? e.data : null;
            if (data && data.__wrappedWorkerError) {
              monacoLog(
                "error",
                "Worker wrapped error: " +
                  data.message +
                  (data.filename
                    ? " at " + data.filename + ":" + data.lineno + ":" + data.colno
                    : "") +
                  (data.stack ? " stack=" + data.stack : "")
              );
            } else if (data && data.__wrappedWorkerRejection) {
              monacoLog("error", "Worker wrapped rejection: " + data.reason);
            }
          });
          worker.addEventListener("messageerror", function () {
            monacoLog("error", "Worker messageerror: " + urlString);
          });
          return worker;
        };
        WorkerWrapper.prototype = OriginalWorker.prototype;
        try {
          Object.setPrototypeOf(WorkerWrapper, OriginalWorker);
        } catch (e) {}
        window.Worker = WorkerWrapper;
        monacoLog("info", "Worker wrapper installed");
      } catch (e) {
        monacoLog(
          "error",
          "Failed to wrap Worker: " +
            (e && e.message ? e.message : String(e)) +
            (e && e.stack ? " stack=" + e.stack : "")
        );
      }
    }
    window.addEventListener("unhandledrejection", function (event) {
      var reason = event && event.reason ? event.reason.toString() : "unknown";
      monacoLog("error", "Unhandled promise rejection: " + reason);
    });
  }

  function applyPending() {
    if (!editor) {
      return;
    }
    if (pendingOptions) {
      editor.updateOptions(pendingOptions);
    }
    if (pendingLanguage) {
      monaco.editor.setModelLanguage(editor.getModel(), pendingLanguage);
    }
    if (pendingTheme) {
      monaco.editor.setTheme(pendingTheme);
    }
    if (typeof pendingValue === "string" && editor.getValue() !== pendingValue) {
      editor.setValue(pendingValue);
    }
    applyBreakpoints();
  }

  function applyBreakpoints() {
    if (!editor) {
      return;
    }
    if (!pendingBreakpoints) {
      return;
    }
    var decorations = pendingBreakpoints.map(function (lineNumber) {
      return {
        range: new monaco.Range(lineNumber, 1, lineNumber, 1),
        options: {
          isWholeLine: true,
          glyphMarginClassName: "monaco-breakpoint",
        },
      };
    });
    breakpointDecorations = editor.deltaDecorations(breakpointDecorations, decorations);
  }

  window.setEditorValue = function (value) {
    pendingValue = value;
    applyPending();
  };

  window.configureEditor = function (options, language, theme) {
    pendingOptions = options || pendingOptions;
    pendingLanguage = language || pendingLanguage;
    pendingTheme = theme || pendingTheme;
    applyPending();
  };

  window.setBreakpoints = function (lines) {
    if (!Array.isArray(lines)) {
      pendingBreakpoints = [];
    } else {
      pendingBreakpoints = lines;
    }
    applyBreakpoints();
  };

  window.focusEditor = function () {
    if (editor) {
      editor.focus();
    }
  };

  window.gotoLine = function (lineNumber) {
    if (!editor) {
      return;
    }
    editor.revealLineInCenter(lineNumber);
    editor.setPosition({ lineNumber: lineNumber, column: 1 });
    editor.focus();
  };

  window.runEditorAction = function (actionId) {
    if (!editor) {
      return;
    }
    var action = editor.getAction(actionId);
    if (action) {
      action.run();
    }
  };

  function collectActionItems() {
    if (!editor || !editor.getSupportedActions) {
      return [];
    }
    var actions = editor.getSupportedActions();
    if (!Array.isArray(actions)) {
      return [];
    }
    var seen = Object.create(null);
    var results = [];
    actions.forEach(function (action) {
      if (!action || !action.id || seen[action.id]) {
        return;
      }
      var isSupported =
        typeof action.isSupported === "function"
          ? action.isSupported()
          : action.enabled !== false;
      var label = action.label || action.alias || action.id;
      seen[action.id] = true;
      results.push({
        id: action.id,
        label: label,
        enabled: !!isSupported,
      });
    });
    return results;
  }

  function buildMenuItems(actions, resolveKeybinding) {
    var results = [];
    if (!Array.isArray(actions)) {
      return results;
    }
    actions.forEach(function (action) {
      if (!action) {
        return;
      }
      if (action.id === "vs.actions.separator") {
        results.push({ kind: "separator" });
        return;
      }
      var hasChildren = Array.isArray(action.actions);
      if (hasChildren) {
        var nested = buildMenuItems(action.actions, resolveKeybinding);
        if (nested.length === 0) {
          return;
        }
        results.push({
          kind: "submenu",
          id: action.id || null,
          label: action.label || action.id,
          children: nested,
        });
        return;
      }
      var enabled =
        typeof action.isSupported === "function"
          ? action.isSupported()
          : action.enabled !== false;
      var label = action.label || action.alias || action.id;
      if (action.id) {
        var keybinding = null;
        if (resolveKeybinding) {
          keybinding = resolveKeybinding(action);
        }
        contextMenuActionMap[action.id] = action;
        results.push({
          kind: "action",
          id: action.id,
          label: label,
          enabled: !!enabled,
          keybinding: keybinding || null,
        });
      }
    });
    return results;
  }

  function collectContextMenuItems() {
    if (!editor) {
      return collectActionItems();
    }
    contextMenuActionMap = Object.create(null);
    try {
      if (editor.getContribution) {
          var controller = editor.getContribution("editor.contrib.contextmenu");
          if (controller && typeof controller._getMenuActions === "function") {
            var model = editor.getModel && editor.getModel();
            var menuId = editor.contextMenuId;
            var actions = controller._getMenuActions(model, menuId);
            var resolveKeybinding = function (action) {
              try {
                if (typeof controller._keybindingFor === "function") {
                  var binding = controller._keybindingFor(action);
                  if (binding && typeof binding.getLabel === "function") {
                    return binding.getLabel();
                  }
                }
              } catch (e) {}
              return null;
            };
            return buildMenuItems(actions, resolveKeybinding);
        }
      }
    } catch (e) {}
    var fallback = collectActionItems();
    return fallback.map(function (item) {
      return { kind: "action", id: item.id, label: item.label, enabled: item.enabled };
    });
  }

  window.runMenuAction = function (actionId) {
    if (!actionId) {
      return;
    }
    window.runEditorAction(actionId);
    var action = contextMenuActionMap ? contextMenuActionMap[actionId] : null;
    if (action && typeof action.run === "function") {
      action.run();
      return;
    }
  };

  window.requestCommandPaletteItems = function () {
    if (!editor) {
      return;
    }
    postMessage("monacoCommandPalette", { actions: collectActionItems() });
  };

  window.undoEditor = function () {
    if (!editor) {
      return;
    }
    editor.trigger("keyboard", "undo", null);
  };

  window.redoEditor = function () {
    if (!editor) {
      return;
    }
    editor.trigger("keyboard", "redo", null);
  };

  window.replaceTextAt = function (
    lineNumber,
    searchText,
    replacementText,
    isRegex,
    isCaseSensitive
  ) {
    if (!editor) {
      return;
    }
    var model = editor.getModel();
    if (!model) {
      return;
    }
    if (lineNumber < 1 || lineNumber > model.getLineCount()) {
      return;
    }
    var maxColumn = model.getLineMaxColumn(lineNumber);
    var range = new monaco.Range(lineNumber, 1, lineNumber, maxColumn);
    var matches = model.findMatches(
      searchText,
      range,
      !!isRegex,
      !!isCaseSensitive,
      null,
      false
    );
    if (!matches || matches.length === 0) {
      return;
    }
    editor.pushUndoStop();
    editor.executeEdits("replaceTextAt", [
      {
        range: matches[0].range,
        text: replacementText,
        forceMoveMarkers: true,
      },
    ]);
    editor.pushUndoStop();
  };

  window.insertText = function (text) {
    if (!editor) {
      return;
    }
    var selection = editor.getSelection();
    if (!selection) {
      return;
    }
    editor.pushUndoStop();
    editor.executeEdits("insertText", [
      {
        range: selection,
        text: text,
        forceMoveMarkers: true,
      },
    ]);
    editor.pushUndoStop();
    editor.focus();
  };

  function startEditor() {
    monacoLog("info", "startEditor");
    ensureMonacoEnvironment();
    require.config({ paths: { vs: "min/vs" } });
    if (typeof require !== "undefined") {
      try {
        require.onError = function (err) {
          monacoLog(
            "error",
            "RequireJS error: " +
              (err && err.message ? err.message : String(err)) +
              (err && err.requireType ? " type=" + err.requireType : "") +
              (err && err.requireModules
                ? " modules=" + err.requireModules.join(",")
                : "")
          );
        };
      } catch (e) {}
    }
    require(["vs/editor/editor.main"], function () {
      monacoLog("info", "editor.main loaded");
      ensureMonacoEnvironment(true);
      if (debugLoggingEnabled) {
        try {
          registerGDScript();
        } catch (e) {
          monacoLog(
            "error",
            "Failed to register gdscript: " +
              (e && e.message ? e.message : String(e)) +
              (e && e.stack ? " stack=" + e.stack : "")
          );
        }
        try {
          registerGodotShader();
        } catch (e) {
          monacoLog(
            "error",
            "Failed to register gdshader: " +
              (e && e.message ? e.message : String(e)) +
              (e && e.stack ? " stack=" + e.stack : "")
          );
        }
      } else {
        registerGDScript();
        registerGodotShader();
      }
      if (debugLoggingEnabled) {
        try {
          var createOptions = Object.assign({}, pendingOptions || {}, {
            value: pendingValue || "",
            language: pendingLanguage || "plaintext",
            theme: pendingTheme || "vs",
          });
          editor = monaco.editor.create(
            document.getElementById("container"),
            createOptions
          );
        } catch (e) {
          monacoLog(
            "error",
            "Failed to create Monaco editor: " +
              (e && e.message ? e.message : String(e)) +
              (e && e.stack ? " stack=" + e.stack : "")
          );
          return;
        }
      } else {
        var createOptions = Object.assign({}, pendingOptions || {}, {
          value: pendingValue || "",
          language: pendingLanguage || "plaintext",
          theme: pendingTheme || "vs",
        });
        editor = monaco.editor.create(
          document.getElementById("container"),
          createOptions
        );
      }
      installDiagnosticsLogging();
      ensureEditorModel();
      logModelState("Editor created:");
      applyPending();
      monacoLog("info", "editor created");
      logModelDiagnostics(editor.getModel(), "editorCreated");

      editor.onDidChangeModelContent(function () {
        postMessage("monacoTextChanged", editor.getValue());
      });

      editor.onDidChangeModel(function () {
        var model = editor.getModel();
        logModelState("Model changed:");
        logModelDiagnostics(model, "modelChanged");
      });

      editor.onDidChangeCursorSelection(function (e) {
        var model = editor.getModel();
        if (!model) {
          return;
        }
        var selection = e.selection;
        var startOffset = model.getOffsetAt({
          lineNumber: selection.startLineNumber,
          column: selection.startColumn,
        });
        var endOffset = model.getOffsetAt({
          lineNumber: selection.endLineNumber,
          column: selection.endColumn,
        });
        postMessage("monacoSelectionChanged", { start: startOffset, end: endOffset });
      });

      editor.onMouseDown(function (e) {
        if (!e || !e.target || !e.target.position) {
          return;
        }
        var targetType = e.target.type;
        if (
          targetType === monaco.editor.MouseTargetType.GUTTER_GLYPH_MARGIN ||
          targetType === monaco.editor.MouseTargetType.GUTTER_LINE_NUMBERS ||
          targetType === monaco.editor.MouseTargetType.GUTTER_LINE_DECORATIONS
        ) {
          postMessage("monacoGutterTapped", e.target.position.lineNumber);
        }
      });

      editor.onContextMenu(function (e) {
        if (!e || !editor) {
          return;
        }
        var model = editor.getModel();
        var selection = editor.getSelection();
        var selectionPayload = null;
        var selectedText = "";
        if (model && selection) {
          selectionPayload = {
            startLineNumber: selection.startLineNumber,
            startColumn: selection.startColumn,
            endLineNumber: selection.endLineNumber,
            endColumn: selection.endColumn,
          };
          selectedText = model.getValueInRange(selection);
        }
        var position = e.target && e.target.position ? e.target.position : null;
        var word = null;
        if (model && position) {
          var wordInfo = model.getWordAtPosition(position);
          if (wordInfo && wordInfo.word) {
            word = wordInfo.word;
          }
        }
        var point = null;
        if (e.event && typeof e.event.posx === "number" && typeof e.event.posy === "number") {
          point = { x: e.event.posx, y: e.event.posy };
        }
        postMessage("monacoContextMenu", {
          position: position,
          selection: selectionPayload,
          selectedText: selectedText,
          word: word,
          point: point,
          actions: collectContextMenuItems(),
        });
        if (e.event && typeof e.event.preventDefault === "function") {
          e.event.preventDefault();
        }
        if (e.event && typeof e.event.stopPropagation === "function") {
          e.event.stopPropagation();
        }
      });

      if (!window.__monacoCommandPaletteKeyHandlerInstalled) {
        window.__monacoCommandPaletteKeyHandlerInstalled = true;
        window.addEventListener(
          "keydown",
          function (ev) {
            if (!editor) {
              return;
            }
            var isCmdOrCtrl = ev.metaKey || ev.ctrlKey;
            var isPalette =
              (isCmdOrCtrl && ev.shiftKey && (ev.key === "P" || ev.key === "p")) ||
              ev.key === "F1";
            if (!isPalette) {
              return;
            }
            if (ev.preventDefault) {
              ev.preventDefault();
            }
            if (ev.stopPropagation) {
              ev.stopPropagation();
            }
            window.requestCommandPaletteItems();
          },
          true
        );
      }

      var attemptedLspScripts = [];
      var tryLoadLspClient = function (src, next) {
        if (!src) {
          next();
          return;
        }
        attemptedLspScripts.push(src);
        loadScript(
          src,
          function () {
            monacoLog("info", "Monaco LSP client script loaded: " + src);
            startLspClient();
          },
          function () {
            next();
          }
        );
      };
      var doneLspLoad = function () {
        monacoLog(
          "warn",
          "Failed to load Monaco LSP client script. Tried: " +
            attemptedLspScripts.join(", ")
        );
      };
      tryLoadLspClient("monaco-lsp-client.js", function () {
        tryLoadLspClient("../monaco-lsp-client.js", function () {
          tryLoadLspClient(lspClientScriptURL, doneLspLoad);
        });
      });

      postMessage("monacoReady", true);
    });
  }

  function registerGDScript() {
    if (gdscriptRegistered) {
      return;
    }
    gdscriptRegistered = true;
    monacoLog("info", "registering gdscript");
    monaco.languages.register({
      id: "gdscript",
      aliases: ["GDScript", "gdscript"],
      extensions: [".gd", ".gdscript"],
    });

    monaco.languages.setLanguageConfiguration("gdscript", {
      comments: { lineComment: "#" },
      brackets: [
        ["{", "}"],
        ["[", "]"],
        ["(", ")"],
      ],
      autoClosingPairs: [
        { open: "{", close: "}" },
        { open: "[", close: "]" },
        { open: "(", close: ")" },
        { open: '"', close: '"', notIn: ["string"] },
        { open: "'", close: "'", notIn: ["string"] },
        { open: '"""', close: '"""' },
        { open: "'''", close: "'''" },
      ],
      surroundingPairs: [
        { open: "{", close: "}" },
        { open: "[", close: "]" },
        { open: "(", close: ")" },
        { open: '"', close: '"' },
        { open: "'", close: "'" },
      ],
      indentationRules: {
        increaseIndentPattern:
          /^\s*(class_name|class|func|if|elif|else|for|while|match|case|try|except|finally)\b.*:\s*(#.*)?$/,
        decreaseIndentPattern: /^\s*(elif|else|case|except|finally)\b.*:\s*(#.*)?$/,
      },
      onEnterRules: [
        {
          beforeText:
            /^\s*(class_name|class|func|if|elif|else|for|while|match|case|try|except|finally)\b.*:\s*(#.*)?$/,
          action: { indentAction: monaco.languages.IndentAction.Indent },
        },
      ],
    });

    monaco.languages.setMonarchTokensProvider("gdscript", {
      keywords: [
        "and",
        "or",
        "not",
        "in",
        "is",
        "as",
        "class",
        "class_name",
        "extends",
        "func",
        "var",
        "const",
        "signal",
        "enum",
        "static",
        "if",
        "elif",
        "else",
        "for",
        "while",
        "match",
        "case",
        "break",
        "continue",
        "return",
        "pass",
        "yield",
        "await",
        "super",
        "self",
        "onready",
        "tool",
        "export",
        "setget",
        "assert",
        "breakpoint",
        "sync",
        "remote",
        "master",
        "puppet",
        "slave",
        "remotesync",
        "mastersync",
        "puppetsync",
        "trait",
        "namespace",
        "when",
      ],
      builtins: [
        "Vector2",
        "Vector2i",
        "Vector3",
        "Vector3i",
        "Vector4",
        "Vector4i",
        "Color",
        "Rect2",
        "Rect2i",
        "Array",
        "Basis",
        "Dictionary",
        "Plane",
        "Quat",
        "RID",
        "Rect3",
        "Transform",
        "Transform2D",
        "Transform3D",
        "AABB",
        "String",
        "NodePath",
        "PoolByteArray",
        "PoolIntArray",
        "PoolRealArray",
        "PoolStringArray",
        "PoolVector2Array",
        "PoolVector3Array",
        "PoolColorArray",
        "bool",
        "int",
        "float",
        "Signal",
        "Callable",
        "StringName",
        "Quaternion",
        "Projection",
        "PackedByteArray",
        "PackedInt32Array",
        "PackedInt64Array",
        "PackedFloat32Array",
        "PackedFloat64Array",
        "PackedStringArray",
        "PackedVector2Array",
        "PackedVector2iArray",
        "PackedVector3Array",
        "PackedVector3iArray",
        "PackedVector4Array",
        "PackedColorArray",
        "JSON",
        "UPNP",
        "OS",
        "IP",
        "JSONRPC",
        "XRVRS",
        "Variant",
        "void",
      ],
      tokenizer: {
        root: [
          [
            /@(abstract|export|export_category|export_color_no_alpha|export_custom|export_dir|export_enum|export_exp_easing|export_file|export_file_path|export_flags|export_flags_2d_navigation|export_flags_2d_physics|export_flags_2d_render|export_flags_3d_navigation|export_flags_3d_physics|export_flags_3d_render|export_flags_avoidance|export_global_dir|export_global_file|export_group|export_multiline|export_node_path|export_placeholder|export_range|export_storage|export_subgroup|export_tool_button|icon|onready|rpc|static_unload|tool|warning_ignore|warning_ignore_restore|warning_ignore_start)\b/,
            "annotation",
          ],
          [/@[a-zA-Z_]\w*/, "annotation"],
          [/\bclass_name\b/, { token: "keyword", next: "@className" }],
          [/\bextends\b/, { token: "keyword", next: "@extendsName" }],
          [/\bclass\b/, { token: "keyword", next: "@classDecl" }],
          [/\benum\b/, { token: "keyword", next: "@enumDecl" }],
          [/\bfunc\b/, { token: "keyword", next: "@functionDecl" }],
          [/\bsignal\b/, { token: "keyword", next: "@signalDecl" }],
          [/\b(?:var|const)\b/, { token: "keyword", next: "@varDecl" }],
          [/^\s*#.*$/, "comment"],
          [/#.*$/, "comment"],
          [/^\s*(get|set)\b(?=\s*:)/, "function"],
          [/\b(?:true|false|null)\b/, "constant.language"],
          [/\b(?:PI|TAU|INF|NAN)\b/, "constant.language"],
          [/0b[01_]+/i, "number.binary"],
          [/0x[0-9a-fA-F_]+/, "number.hex"],
          [/([0-9][0-9_]*)?\.[0-9_]*([eE][\-+]?[0-9_]+)?/, "number.float"],
          [/[0-9][0-9_]*[eE][\-+]?[0-9_]+/, "number.float"],
          [/-?[0-9][0-9_]*/, "number"],
          [/(->)\s*([a-zA-Z_]\w*)/, ["operator", "type.identifier"]],
          [/(\bis\b|\bas\b)\s+([a-zA-Z_]\w*)/, ["keyword", "type.identifier"]],
          [/\bNodePath\b/, { token: "type", next: "@nodePathCtor" }],
          [
            /\b(get_node_or_null|has_node|has_node_and_resource|find_node|get_node)\b/,
            { token: "function", next: "@nodePathCall" },
          ],
          [/(\^|&)"([^"\\]|\\.)*"/, "string"],
          [/(\^|&)'([^'\\]|\\.)*'/, "string"],
          [/\$[A-Za-z0-9_\/\.\:%-]+/, "string"],
          [/%[A-Za-z0-9_\/\.\:%-]+/, "string"],
          [/"""/, "string", "@tripleDouble"],
          [/'''/, "string", "@tripleSingle"],
          [/"/, "string", "@stringDouble"],
          [/'/, "string", "@stringSingle"],
          [/([.])\s*([a-zA-Z_]\w*)/, ["delimiter", "variable.other.property"]],
          [/[\[\]{}()]/, "@brackets"],
          [/[;,.]/, "delimiter"],
          [
            /\b(and|or|not)\b/,
            "operator",
          ],
          [/(?:&&|\|\||<<=|>>=|<<|>>|\^|~|<=|>=|==|<|>|!=|!|->|\+=|-=|\*\*=|\*=|\^=|\/=|%=|&=|~=|\|=|\*\*|\*|\/|%|\+|-|=)/,
            "operator",
          ],
          [/\b[A-Z][A-Za-z0-9_]*\b/, "type.identifier"],
          [/\b[A-Z_][A-Z_0-9]*\b/, "constant"],
          [
            /\b(?!if\b|elif\b|else\b|for\b|while\b|match\b|case\b|return\b|break\b|continue\b|pass\b|yield\b|await\b|func\b|class\b|signal\b|var\b|const\b)[a-zA-Z_]\w*(?=\s*\()/,
            "function",
          ],
          [
            /[a-zA-Z_][\w]*/,
            {
              cases: {
                "@keywords": "keyword",
                "@builtins": "type",
                "@default": "identifier",
              },
            },
          ],
          { include: "@whitespace" },
        ],
        className: [
          [/\s+/, "white"],
          [/[a-zA-Z_]\w*(?:\.[a-zA-Z_]\w*)?/, "type.identifier", "@pop"],
          ["", "", "@pop"],
        ],
        extendsName: [
          [/\s+/, "white"],
          [/[a-zA-Z_]\w*(?:\.[a-zA-Z_]\w*)?/, "type.identifier", "@pop"],
          ["", "", "@pop"],
        ],
        classDecl: [
          [/\s+/, "white"],
          [/[a-zA-Z_]\w*/, "type.identifier", "@pop"],
          ["", "", "@pop"],
        ],
        enumDecl: [
          [/\s+/, "white"],
          [/[a-zA-Z_]\w*/, "type.identifier"],
          [/\{/, { token: "delimiter.bracket", next: "@enumBody" }],
          ["", "", "@pop"],
        ],
        enumBody: [
          [/\s+/, "white"],
          [/}/, { token: "delimiter.bracket", next: "@pop" }],
          [/,/, "delimiter"],
          [/[a-zA-Z_]\w*/, "constant"],
          [/[0-9][0-9_]*/, "number"],
        ],
        functionDecl: [
          [/\s+/, "white"],
          [/[a-zA-Z_]\w*/, "function", "@maybeParams"],
          [/\(/, { token: "delimiter.parenthesis", next: "@params" }],
          ["", "", "@pop"],
        ],
        signalDecl: [
          [/\s+/, "white"],
          [/[a-zA-Z_]\w*/, "function", "@maybeParams"],
          [/\(/, { token: "delimiter.parenthesis", next: "@params" }],
          ["", "", "@pop"],
        ],
        maybeParams: [
          [/\s+/, "white"],
          [/\(/, { token: "delimiter.parenthesis", next: "@params" }],
          ["", "", "@pop"],
        ],
        params: [
          [/\s+/, "white"],
          [/\)/, { token: "delimiter.parenthesis", next: "@pop" }],
          [/,/, "delimiter"],
          [/(:)\s*([a-zA-Z_]\w*)/, ["delimiter", "type.identifier"]],
          [/=/, "operator"],
          [/[a-zA-Z_]\w*/, "variable.parameter"],
        ],
        varDecl: [
          [/\s+/, "white"],
          [/[a-zA-Z_]\w*/, "variable", "@varDeclAfterName"],
          ["", "", "@pop"],
        ],
        varDeclAfterName: [
          [/\s+/, "white"],
          [/(set|get)\b/, "function"],
          [/(setget)\b/, "keyword"],
          [/(:)\s*([a-zA-Z_]\w*)/, ["delimiter", "type.identifier"]],
          [/(=|:=)/, "operator", "@pop"],
          [/,/, "delimiter"],
          [/$/, "", "@pop"],
        ],
        nodePathCtor: [
          [/\s+/, "white"],
          [/\(/, "delimiter.parenthesis"],
          [/"/, "string", "@nodePathStringDouble"],
          [/'/, "string", "@nodePathStringSingle"],
          [/\)/, { token: "delimiter.parenthesis", next: "@pop" }],
          ["", "", "@pop"],
        ],
        nodePathCall: [
          [/\s+/, "white"],
          [/\(/, "delimiter.parenthesis"],
          [/"/, "string", "@nodePathStringDouble"],
          [/'/, "string", "@nodePathStringSingle"],
          [/\)/, { token: "delimiter.parenthesis", next: "@pop" }],
          ["", "", "@pop"],
        ],
        nodePathStringDouble: [
          [/%/, "keyword"],
          [/\\./, "constant.character.escape"],
          [/[^\\"]+/, "string"],
          [/"/, "string", "@pop"],
        ],
        nodePathStringSingle: [
          [/%/, "keyword"],
          [/\\./, "constant.character.escape"],
          [/[^\\']+/, "string"],
          [/'/, "string", "@pop"],
        ],
        tripleDouble: [
          [/"""/, "string", "@pop"],
          [/[^]+/, "string"],
        ],
        tripleSingle: [
          [/'''/, "string", "@pop"],
          [/[^]+/, "string"],
        ],
        stringDouble: [
          [/%(?:\d+\$)?[+-]?(?:\d+)?(?:\.\d+)?[sdif]/, "constant.character.format"],
          [/\{[^"\\n}]*\}/, "constant.character.format"],
          [/\\./, "constant.character.escape"],
          [/[^\\%"]+/, "string"],
          [/"/, "string", "@pop"],
        ],
        stringSingle: [
          [/%(?:\d+\$)?[+-]?(?:\d+)?(?:\.\d+)?[sdif]/, "constant.character.format"],
          [/\{[^'\\n}]*\}/, "constant.character.format"],
          [/\\./, "constant.character.escape"],
          [/[^\\%']+/, "string"],
          [/'/, "string", "@pop"],
        ],
        whitespace: [[/[ \t\r\n]+/, ""]],
      },
    });

    monaco.languages.registerDocumentFormattingEditProvider("gdscript", {
      provideDocumentFormattingEdits: function (model, options) {
        var tabSize = options && options.tabSize ? options.tabSize : 4;
        var insertSpaces =
          options && options.insertSpaces !== undefined ? options.insertSpaces : true;
        var indentUnit = insertSpaces ? " ".repeat(tabSize) : "\t";
        var lineCount = model.getLineCount();
        var edits = [];
        var indentLevel = 0;

        function indentationLevelForLine(lineText) {
          var match = /^\s*/.exec(lineText);
          var indent = match ? match[0] : "";
          if (!indent) {
            return 0;
          }
          var columns = 0;
          for (var i = 0; i < indent.length; i++) {
            columns += indent[i] === "\t" ? tabSize : 1;
          }
          return Math.floor(columns / tabSize);
        }

        function shouldDedent(lineText) {
          return /^(elif|else|case|except|finally)\b/.test(lineText);
        }

        function endsWithColon(lineText) {
          var cleaned = lineText.split("#")[0].trim();
          return /:\s*$/.test(cleaned);
        }

        for (var lineNumber = 1; lineNumber <= lineCount; lineNumber++) {
          var line = model.getLineContent(lineNumber);
          var trimmed = line.trim();
          if (trimmed.length === 0) {
            if (line.length > 0) {
              edits.push({
                range: new monaco.Range(lineNumber, 1, lineNumber, line.length + 1),
                text: "",
              });
            }
            continue;
          }
          var actualIndentLevel = indentationLevelForLine(line);
          var currentIndentLevel = indentLevel;
          if (shouldDedent(trimmed)) {
            currentIndentLevel = Math.max(0, currentIndentLevel - 1);
          }
          if (actualIndentLevel < currentIndentLevel) {
            currentIndentLevel = actualIndentLevel;
          }
          var desiredIndent = indentUnit.repeat(currentIndentLevel);
          var actualIndentMatch = /^\s*/.exec(line);
          var actualIndent = actualIndentMatch ? actualIndentMatch[0] : "";
          if (actualIndent !== desiredIndent) {
            edits.push({
              range: new monaco.Range(lineNumber, 1, lineNumber, actualIndent.length + 1),
              text: desiredIndent,
            });
          }
          indentLevel = currentIndentLevel;
          if (endsWithColon(trimmed)) {
            indentLevel += 1;
          }
        }
        return edits;
      },
    });
  }

  function registerGodotShader() {
    if (gdshaderRegistered) {
      return;
    }
    gdshaderRegistered = true;
    monacoLog("info", "registering gdshader");
    monaco.languages.register({
      id: "gdshader",
      aliases: ["Godot Shader", "gdshader", "gdshaderinclude"],
      extensions: [".gdshader", ".gdshaderinclude", ".gdshaderinc"],
    });

    monaco.languages.setLanguageConfiguration("gdshader", {
      comments: {
        lineComment: "//",
        blockComment: ["/*", "*/"],
      },
      brackets: [
        ["{", "}"],
        ["[", "]"],
        ["(", ")"],
      ],
      autoClosingPairs: [
        { open: "{", close: "}" },
        { open: "[", close: "]" },
        { open: "(", close: ")" },
        { open: '"', close: '"', notIn: ["string", "comment"] },
        { open: "'", close: "'", notIn: ["string", "comment"] },
        { open: "/*", close: "*/", notIn: ["string"] },
      ],
      surroundingPairs: [
        { open: "{", close: "}" },
        { open: "[", close: "]" },
        { open: "(", close: ")" },
        { open: '"', close: '"' },
        { open: "'", close: "'" },
      ],
      indentationRules: {
        increaseIndentPattern: /{\s*(?:\/\/.*|#.*)?$/,
        decreaseIndentPattern: /^\s*}/,
      },
      onEnterRules: [
        {
          beforeText: /{\s*$/,
          afterText: /^\s*}/,
          action: { indentAction: monaco.languages.IndentAction.IndentOutdent },
        },
        {
          beforeText: /{\s*$/,
          action: { indentAction: monaco.languages.IndentAction.Indent },
        },
        {
          beforeText: /^\s*}/,
          action: { indentAction: monaco.languages.IndentAction.Outdent },
        },
      ],
    });

    monaco.languages.setMonarchTokensProvider("gdshader", {
      keywords: ["shader_type", "render_mode", "struct"],
      controlKeywords: [
        "if",
        "else",
        "do",
        "while",
        "for",
        "continue",
        "break",
        "switch",
        "case",
        "default",
        "return",
        "discard",
      ],
      modifierKeywords: [
        "const",
        "global",
        "instance",
        "uniform",
        "varying",
        "in",
        "out",
        "inout",
        "flat",
        "smooth",
      ],
      precisionKeywords: ["lowp", "mediump", "highp", "precision"],
      typeKeywords: [
        "void",
        "bool",
        "int",
        "uint",
        "float",
        "double",
        "vec2",
        "vec3",
        "vec4",
        "bvec2",
        "bvec3",
        "bvec4",
        "ivec2",
        "ivec3",
        "ivec4",
        "uvec2",
        "uvec3",
        "uvec4",
        "mat2",
        "mat3",
        "mat4",
        "sampler2D",
        "sampler2DArray",
        "sampler3D",
        "samplerCube",
        "samplerCubeArray",
        "samplerExternalOES",
      ],
      builtins: [
        "COLOR",
        "ALBEDO",
        "ALPHA",
        "ALPHA_SCISSOR",
        "ALPHA_HASH_SCALE",
        "METALLIC",
        "ROUGHNESS",
        "SPECULAR",
        "EMISSION",
        "NORMAL",
        "NORMAL_MAP",
        "NORMAL_MAP_DEPTH",
        "RIM",
        "RIM_TINT",
        "CLEARCOAT",
        "CLEARCOAT_GLOSS",
        "ANISOTROPY",
        "ANISOTROPY_FLOW",
        "SSS_STRENGTH",
        "AO",
        "AO_LIGHT_AFFECT",
        "REFRACTION",
        "REFRACTION_ROUGHNESS",
        "UV",
        "UV2",
        "VERTEX",
        "NORMAL_MATRIX",
        "TANGENT",
        "BINORMAL",
        "WORLD_MATRIX",
        "MODEL_MATRIX",
        "VIEW_MATRIX",
        "PROJECTION_MATRIX",
        "INV_VIEW_MATRIX",
        "INV_PROJECTION_MATRIX",
        "INV_VIEW_PROJECTION_MATRIX",
        "SCREEN_TEXTURE",
        "DEPTH_TEXTURE",
        "TIME",
        "PI",
        "TAU",
      ],
      functions: [
        "sin",
        "cos",
        "tan",
        "asin",
        "acos",
        "atan",
        "radians",
        "degrees",
        "pow",
        "exp",
        "log",
        "exp2",
        "log2",
        "sqrt",
        "inversesqrt",
        "abs",
        "sign",
        "floor",
        "ceil",
        "fract",
        "mod",
        "min",
        "max",
        "clamp",
        "mix",
        "step",
        "smoothstep",
        "length",
        "distance",
        "dot",
        "cross",
        "normalize",
        "reflect",
        "refract",
        "texture",
        "textureLod",
        "vertex",
        "fragment",
        "light",
        "start",
        "process",
        "sky",
        "fog",
      ],
      tokenizer: {
        root: [
          [/\b(shader_type|render_mode)\b/, { token: "keyword", next: "@classifier" }],
          [/\bstruct\b/, { token: "keyword", next: "@structName" }],
          [/^\s*#.*$/, "preprocessor"],
          [/\/\/.*$/, "comment"],
          [/\/\*/, "comment", "@comment"],
          [
            /\b(?:source_color|hint_(?:color|range|(?:black_)?albedo|normal|(?:default_)?(?:white|black)|aniso|anisotropy|roughness_(?:[rgba]|normal|gray))|filter_(?:nearest|linear)(?:_mipmap(?:_anisotropic)?)?|repeat_(?:en|dis)able)\b/,
            "type.annotation",
          ],
          [/\b(?:E|PI|TAU)\b/, "constant.language"],
          [/\b0[xX][0-9a-fA-F]+\b/, "number.hex"],
          [/\b\d+(\.\d+)?([eE][\-+]?\d+)?\b/, "number"],
          [/\b(?:true|false)\b/, "constant.language"],
          [/"([^"\\]|\\.)*"/, "string"],
          [/'([^'\\]|\\.)*'/, "string"],
          [
            /\b[a-zA-Z_]\w*(?=(?:\s*\[\s*\w*\s*\])?\s+[a-zA-Z_]\w*\b)/,
            "type.identifier",
          ],
          [
            /\b[a-zA-Z_]\w*(?=\s*\[\s*\w*\s*\]\s*[(])|\b[A-Z]\w*(?=\s*[(])/,
            "type.constructor",
          ],
          [
            /\b(?!if\b|else\b|do\b|while\b|for\b|continue\b|break\b|switch\b|case\b|default\b|return\b|discard\b|struct\b)[a-zA-Z_]\w*(?=\s*[(])/,
            "function",
          ],
          [/([.])\s*([xyzw]{2,4}|[rgba]{2,4}|[stpq]{2,4})\b/, ["delimiter", "variable.other.property"]],
          [/([.])\s*([a-zA-Z_]\w*)\b(?!\s*\()/, ["delimiter", "variable.other.property"]],
          [/\b[A-Z][A-Z_0-9]*\b/, "variable.language"],
          [/[\[\]{}()]/, "@brackets"],
          [/[;,.]/, "delimiter"],
          [/:/, "operator"],
          [
            /\<\<\=?|\>\>\=?|[-+*/&|<>=!]\=|\&\&|[|][|]|[-+~!*/%<>&^|=]/,
            "operator",
          ],
          [
            /[a-zA-Z_][\w]*/,
            {
              cases: {
                "@keywords": "keyword",
                "@controlKeywords": "keyword.control",
                "@modifierKeywords": "storage.modifier",
                "@precisionKeywords": "storage.type",
                "@typeKeywords": "type",
                "@builtins": "variable.language",
                "@functions": "function",
                "@default": "identifier",
              },
            },
          ],
          { include: "@whitespace" },
        ],
        classifier: [
          [/\s+/, "white"],
          [/^\s*#.*$/, "preprocessor"],
          [/\/\/.*$/, "comment"],
          [/\/\*/, "comment", "@comment"],
          [/[,]/, "delimiter"],
          [/[;]/, { token: "delimiter", next: "@pop" }],
          [/[a-zA-Z_][\w]*/, "type.identifier"],
        ],
        structName: [
          [/\s+/, "white"],
          [/[a-zA-Z_][\w]*/, { token: "type.identifier", next: "@pop" }],
          ["", "", "@pop"],
        ],
        comment: [
          [/[^\/*]+/, "comment"],
          [/\*\//, "comment", "@pop"],
          [/[\/*]/, "comment"],
        ],
        whitespace: [[/[ \t\r\n]+/, ""]],
      },
    });

    monaco.languages.registerDocumentFormattingEditProvider("gdshader", {
      provideDocumentFormattingEdits: function (model, options) {
        var tabSize = options && options.tabSize ? options.tabSize : 4;
        var insertSpaces =
          options && options.insertSpaces !== undefined ? options.insertSpaces : true;
        var indentUnit = insertSpaces ? " ".repeat(tabSize) : "\t";
        var lineCount = model.getLineCount();
        var edits = [];
        var indentLevel = 0;

        function isPreprocessor(lineText) {
          return /^\s*#/.test(lineText);
        }

        function stripStringsAndComments(lineText) {
          var withoutLineComments = lineText.replace(/\/\/.*$/, "");
          var withoutBlockComments = withoutLineComments.replace(/\/\*.*\*\//g, "");
          var withoutDoubleStrings = withoutBlockComments.replace(/"([^"\\]|\\.)*"/g, "");
          return withoutDoubleStrings.replace(/'([^'\\]|\\.)*'/g, "");
        }

        function countMatches(re, text) {
          var matches = text.match(re);
          return matches ? matches.length : 0;
        }

        for (var lineNumber = 1; lineNumber <= lineCount; lineNumber++) {
          var line = model.getLineContent(lineNumber);
          var trimmed = line.trim();
          if (trimmed.length === 0) {
            if (line.length > 0) {
              edits.push({
                range: new monaco.Range(lineNumber, 1, lineNumber, line.length + 1),
                text: "",
              });
            }
            continue;
          }

          var currentIndentLevel = indentLevel;
          if (/^\}/.test(trimmed)) {
            currentIndentLevel = Math.max(0, currentIndentLevel - 1);
          }

          var desiredIndent = isPreprocessor(trimmed)
            ? ""
            : indentUnit.repeat(currentIndentLevel);
          var actualIndentMatch = /^\s*/.exec(line);
          var actualIndent = actualIndentMatch ? actualIndentMatch[0] : "";
          if (actualIndent !== desiredIndent) {
            edits.push({
              range: new monaco.Range(lineNumber, 1, lineNumber, actualIndent.length + 1),
              text: desiredIndent,
            });
          }

          if (!isPreprocessor(trimmed)) {
            var braceSource = stripStringsAndComments(line);
            var openCount = countMatches(/\{/g, braceSource);
            var closeCount = countMatches(/\}/g, braceSource);
            if (/^\}/.test(trimmed)) {
              closeCount = Math.max(0, closeCount - 1);
            }
            indentLevel = Math.max(0, currentIndentLevel + openCount - closeCount);
          } else {
            indentLevel = currentIndentLevel;
          }
        }

        return edits;
      },
    });
  }

  if (document.readyState === "loading") {
    window.addEventListener("load", startEditor);
  } else {
    startEditor();
  }
})();
