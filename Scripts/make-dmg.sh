#!/bin/bash
# Builds a distributable DMG: Lauda.app + Applications symlink to drag into.
#
# Optional (requires Apple Developer Program) — sign for frictionless install:
#   SIGN_IDENTITY="Developer ID Application: Seu Nome (TEAMID)" Scripts/make-dmg.sh
# and then notarize the result:
#   xcrun notarytool submit build/Lauda-<versao>.dmg --keychain-profile <perfil> --wait
#   xcrun stapler staple build/Lauda-<versao>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

Scripts/build-app.sh release

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/Lauda.app/Contents/Info.plist)"
DMG="build/Lauda-${VERSION}.dmg"
STAGING="build/dmg-staging"
VOLNAME="Lauda"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --sign "$SIGN_IDENTITY" build/Lauda.app
fi

hdiutil detach "/Volumes/$VOLNAME" >/dev/null 2>&1 || true
rm -rf "$STAGING" "$DMG" build/tmp.dmg
mkdir -p "$STAGING"
cp -R build/Lauda.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

cat > "$STAGING/How to Install.txt" <<'EOF'
How to install Lauda

1. Drag Lauda into the Applications folder.
2. Open Lauda from the Applications folder.

The first time, macOS may say it couldn't verify the app (it isn't
signed by an Apple-identified developer yet). If that happens:

   System Settings → Privacy & Security → scroll to the bottom →
   click "Open Anyway" and confirm.

You only need to do this once. Happy writing! ✍️

----------------------------------------------------------------------

Como instalar o Lauda

1. Arraste o Lauda para a pasta Applications (Aplicativos).
2. Abra o Lauda a partir da pasta Aplicativos.

Na primeira vez, o macOS pode avisar que não conseguiu verificar o app
(ele ainda não é assinado por um desenvolvedor identificado pela Apple).
Se isso acontecer:

   Ajustes do Sistema → Privacidade e Segurança → role até o final →
   clique em "Abrir Mesmo Assim" e confirme.

Isso só é necessário uma única vez. Bom texto! ✍️
EOF

hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -format UDRW -ov build/tmp.dmg >/dev/null

# Mount briefly to give the volume the app icon.
MOUNT_DIR="$(hdiutil attach build/tmp.dmg -nobrowse | grep -o '/Volumes/.*$' | tail -1)"
if [[ -f Resources/AppIcon.icns && -d "$MOUNT_DIR" ]]; then
    cp Resources/AppIcon.icns "$MOUNT_DIR/.VolumeIcon.icns"
    xcrun SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi
hdiutil detach "$MOUNT_DIR" >/dev/null

hdiutil convert build/tmp.dmg -format UDZO -o "$DMG" >/dev/null
rm -f build/tmp.dmg
rm -rf "$STAGING"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" "$DMG"
fi

echo "OK: $DMG"
