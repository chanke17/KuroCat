#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build/module-cache" "$ROOT/review"
swiftc -swift-version 5 -O -module-cache-path "$ROOT/.build/module-cache" \
    "$ROOT/Sources/KeyMap.swift" "$ROOT/Sources/InputEngine.swift" \
    "$ROOT/Sources/CoatPatterns.swift" "$ROOT/Sources/CatPhysics.swift" \
    "$ROOT/Sources/ArtworkRenderer.swift" "$ROOT/Sources/CatRenderer.swift" \
    "$ROOT/tests/artwork/main.swift" -o "$ROOT/.build/check-artwork" \
    -framework AppKit -framework CoreGraphics -framework QuartzCore -framework IOKit -framework ApplicationServices
for character in hood blob; do
    KUROCAT_ART_ROOT="$ROOT/Resources/CustomCharacters" "$ROOT/.build/check-artwork" "$character" "$ROOT/review"
done
