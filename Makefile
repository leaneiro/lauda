.PHONY: app run dev icon clean

app:
	Scripts/build-app.sh release

run: app
	@osascript -e 'quit app "MarkEditor"' 2>/dev/null || true
	@sleep 1
	open build/MarkEditor.app

dev:
	swift build

icon:
	Scripts/make-icon.sh

clean:
	rm -rf .build build
