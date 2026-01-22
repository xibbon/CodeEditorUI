MONACO_VERSION ?= 0.55.1
MONACO_URL ?= https://github.com/microsoft/monaco-editor/archive/refs/tags/v$(MONACO_VERSION).tar.gz
MONACO_BUNDLE_DIR ?= Sources/CodeEditorUI/Resources/monaco.bundle

prep:
	curl -L -o monaco-editor-$(MONACO_VERSION).tar.gz https://registry.npmjs.org/monaco-editor/-/monaco-editor-$(MONACO_VERSION).tgz
	mkdir -p $(MONACO_BUNDLE_DIR) || true
	tar xzvf monaco-editor-$(MONACO_VERSION).tar.gz --strip-components=1 -C $(MONACO_BUNDLE_DIR) package/min

#
# This expects a recent monaco-editor checkout in ../monaco-editor
bring-lsp:
	bash scripts/build-monaco-lsp.sh
