#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MONACO_LSP_DIR="${MONACO_LSP_DIR:-"$ROOT_DIR/../monaco-editor/monaco-lsp-client"}"
OUT_DIR="${OUT_DIR:-"$ROOT_DIR/Sources/CodeEditorUI/Resources"}"
OUT_FILE="${OUT_FILE:-"$OUT_DIR/monaco-lsp-client.js"}"

if [[ ! -d "$MONACO_LSP_DIR" ]]; then
  echo "monaco-lsp-client not found at: $MONACO_LSP_DIR" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

pushd "$MONACO_LSP_DIR" >/dev/null

if [[ ! -d node_modules ]]; then
  npm install
fi

TMP_CONFIG="$MONACO_LSP_DIR/.rolldown.iife.mjs"
cat <<'CONFIG' > "$TMP_CONFIG"
import { join } from 'path';
import { defineConfig } from 'rolldown';

export default defineConfig({
  input: {
    index: join(import.meta.dirname, './src/index.ts')
  },
  output: {
    dir: join(import.meta.dirname, './out-iife'),
    format: 'iife',
    name: 'MonacoLspClient',
    globals: { 'monaco-editor-core': 'monaco' }
  },
  external: ['monaco-editor-core']
});
CONFIG

if [[ -x ./node_modules/.bin/rolldown ]]; then
  ./node_modules/.bin/rolldown -c "$TMP_CONFIG"
else
  npx rolldown -c "$TMP_CONFIG"
fi

rm -f "$TMP_CONFIG"

cp -f "$MONACO_LSP_DIR/out-iife/index.js" "$OUT_FILE"

PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
else
  echo "python3/python not found; cannot post-process bundle." >&2
  exit 1
fi

OUT_FILE="$OUT_FILE" "$PYTHON_BIN" - <<'PY'
import os
import re
import sys
from pathlib import Path

path = Path(os.environ["OUT_FILE"])
data = path.read_text(encoding="utf-8")

def replace_literal(old, new, required=True, desc="literal"):
    global data
    if old not in data:
        if required:
            print(f"postprocess: expected {desc} not found", file=sys.stderr)
            sys.exit(1)
        return
    data = data.replace(old, new)

def replace_regex(pattern, repl, required=True, desc="regex"):
    global data
    data, count = re.subn(pattern, repl, data, flags=re.MULTILINE | re.DOTALL)
    if required and count == 0:
        print(f"postprocess: expected {desc} not found", file=sys.stderr)
        sys.exit(1)

replace_literal("filterText: lspItem.filterText,", "filterText: lspItem.filterText || lspItem.label,", desc="filterText fallback")

replace_regex(
    r"\n\s*if \(!range\) range = monaco_editor_core\.Range\.fromPositions\(position, position\);",
    "",
    desc="remove default completion range"
)

# Always send completion context, even without triggerCharacter.
if "completionContext" not in data:
    replace_regex(
        r"const result = await this\._client\.server\.textDocumentCompletion\(\{\s*textDocument: translated\.textDocument,\s*position: translated\.position,\s*context: context\.triggerCharacter \? \{\s*triggerKind: toLspCompletionTriggerKind\(context\.triggerKind\),\s*triggerCharacter: context\.triggerCharacter\s*\} : void 0\s*\}\);",
        "const completionContext = {\\n\\t\\t\\t\\t\\ttriggerKind: toLspCompletionTriggerKind(context.triggerKind)\\n\\t\\t\\t\\t};\\n\\t\\t\\t\\tif (context.triggerCharacter) completionContext.triggerCharacter = context.triggerCharacter;\\n\\t\\t\\t\\tconst result = await this._client.server.textDocumentCompletion({\\n\\t\\t\\t\\t\\ttextDocument: translated.textDocument,\\n\\t\\t\\t\\t\\tposition: translated.position,\\n\\t\\t\\t\\t\\tcontext: completionContext\\n\\t\\t\\t\\t});",
        desc="completion context patch"
    )

path.write_text(data, encoding="utf-8")
PY

popd >/dev/null

echo "Wrote bundle: $OUT_FILE"
