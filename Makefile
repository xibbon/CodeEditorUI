MONACO_VERSION ?= 0.55.1
MONACO_URL ?= https://github.com/microsoft/monaco-editor/archive/refs/tags/v$(MONACO_VERSION).tar.gz
MONACO_BUNDLE_DIR ?= Sources/CodeEditorUI/Resources/monaco.bundle

prep:
	curl -L -o monaco-editor-$(MONACO_VERSION).tar.gz https://registry.npmjs.org/monaco-editor/-/monaco-editor-$(MONACO_VERSION).tgz
	tar xzvf monaco-editor-$(MONACO_VERSION).tar.gz

monaco-bundle:
	bash Plugins/MonacoDownloader/download-monaco.sh "$(MONACO_BUNDLE_DIR)" "$(MONACO_URL)" "$(MONACO_VERSION)"
