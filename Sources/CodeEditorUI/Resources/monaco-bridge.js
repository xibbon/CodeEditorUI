(function () {
  var editor = null;
  var config = window.monacoConfig || {};
  var pendingValue = typeof config.initialValue === "string" ? config.initialValue : "";
  var pendingOptions = config.options || {};
  var pendingLanguage = config.language || "plaintext";
  var pendingTheme = config.theme || "vs";
  var pendingBreakpoints = [];
  var breakpointDecorations = [];
  var gdscriptRegistered = false;
  var debugLoggingEnabled = !!config.debugLoggingEnabled;

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

  if (debugLoggingEnabled) {
    monacoLog("info", "script loaded");
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
    window.addEventListener("error", function (event) {
      monacoLog(
        "error",
        "JS Error: " +
          event.message +
          " at " +
          event.filename +
          ":" +
          event.lineno +
          ":" +
          event.colno
      );
    });
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
    require.config({ paths: { vs: "min/vs" } });
    require(["vs/editor/editor.main"], function () {
      monacoLog("info", "editor.main loaded");
      registerGDScript();
      var createOptions = Object.assign({}, pendingOptions || {}, {
        value: pendingValue || "",
        language: pendingLanguage || "plaintext",
        theme: pendingTheme || "vs",
      });
      editor = monaco.editor.create(document.getElementById("container"), createOptions);
      applyPending();
      monacoLog("info", "editor created");

      editor.onDidChangeModelContent(function () {
        postMessage("monacoTextChanged", editor.getValue());
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
      ],
      builtins: [
        "bool",
        "int",
        "float",
        "String",
        "Array",
        "Dictionary",
        "Vector2",
        "Vector2i",
        "Vector3",
        "Vector3i",
        "Vector4",
        "Vector4i",
        "Rect2",
        "Rect2i",
        "Transform2D",
        "Transform3D",
        "Basis",
        "Color",
        "NodePath",
        "RID",
        "Callable",
        "Signal",
        "PackedByteArray",
        "PackedInt32Array",
        "PackedInt64Array",
        "PackedFloat32Array",
        "PackedFloat64Array",
        "PackedStringArray",
        "PackedVector2Array",
        "PackedVector3Array",
        "PackedVector4Array",
        "PackedColorArray",
      ],
      tokenizer: {
        root: [
          [/^\s*#.*$/, "comment"],
          [/#.*$/, "comment"],
          [/\b0[xX][0-9a-fA-F]+\b/, "number.hex"],
          [/\b\d+(\.\d+)?([eE][\-+]?\d+)?\b/, "number"],
          [/"""/, "string", "@tripleDouble"],
          [/'''/, "string", "@tripleSingle"],
          [/"([^"\\]|\\.)*"/, "string"],
          [/'([^'\\]|\\.)*'/, "string"],
          [/[\[\]{}()]/, "@brackets"],
          [/[;,.]/, "delimiter"],
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
        tripleDouble: [
          [/"""/, "string", "@pop"],
          [/[^]+/, "string"],
        ],
        tripleSingle: [
          [/'''/, "string", "@pop"],
          [/[^]+/, "string"],
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
          var currentIndentLevel = indentLevel;
          if (shouldDedent(trimmed)) {
            currentIndentLevel = Math.max(0, currentIndentLevel - 1);
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

  if (document.readyState === "loading") {
    window.addEventListener("load", startEditor);
  } else {
    startEditor();
  }
})();
