#!/usr/bin/env bash
# Renders the Warren SVGs into a macOS .icns and menu bar template PNGs.
# Requires librsvg:  brew install librsvg
set -euo pipefail

cd "$(dirname "$0")"

command -v rsvg-convert >/dev/null || {
  echo "rsvg-convert not found. Run: brew install librsvg" >&2
  exit 1
}

# --- App icon -----------------------------------------------------------
# macOS does not mask app icons for you, so the rounded body and its inset
# are already baked into the 1024px artwork.

rm -rf Warren.iconset && mkdir Warren.iconset

for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" \
            "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" \
            "512:512x512" "1024:512x512@2x"; do
  px="${spec%%:*}"
  name="${spec##*:}"
  rsvg-convert -w "$px" -h "$px" warren-appicon.svg -o "Warren.iconset/icon_${name}.png"
done

iconutil -c icns Warren.iconset -o Warren.icns
echo "wrote Warren.icns"

# --- Menu bar icons -----------------------------------------------------
# The "Template" suffix is what tells AppKit to tint these automatically.
# macOS menu bars use @1x and @2x only; there is no @3x on the Mac.

for base in WarrenTemplate WarrenOfflineTemplate; do
  rsvg-convert -w 18 -h 18 "${base}.svg" -o "${base}.png"
  rsvg-convert -w 36 -h 36 "${base}.svg" -o "${base}@2x.png"
done
echo "wrote menu bar PNGs"

# --- Wiring it up -------------------------------------------------------
# 1. Drag Warren.icns onto the app target's App Icon slot, or drop the
#    iconset PNGs into an AppIcon image set in Assets.xcassets.
# 2. Drag the menu bar PNGs into Assets.xcassets as an image set named
#    "WarrenTemplate", then set Render As = Template Image in the inspector.
# 3. In code:
#       let image = NSImage(named: "WarrenTemplate")!
#       image.isTemplate = true
#       statusItem.button?.image = image
#    Setting isTemplate explicitly is belt and braces; the name suffix
#    usually handles it, but not when the asset is loaded from a bundle
#    other than main.
