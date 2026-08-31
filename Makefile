.PHONY: app run dev icon clean

app:
	Scripts/build-app.sh release

run: app
	open build/MarkEditor.app

dev:
	swift build

icon:
	Scripts/make-icon.sh

clean:
	rm -rf .build build
