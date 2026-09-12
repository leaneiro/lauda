.PHONY: app run dev icon dmg clean

dmg:
	Scripts/make-dmg.sh

app:
	Scripts/build-app.sh release

run: app
	@osascript -e 'quit app "Lauda"' 2>/dev/null || true
	@sleep 1
	open build/Lauda.app

dev:
	swift build

icon:
	Scripts/make-icon.sh

clean:
	rm -rf .build build
