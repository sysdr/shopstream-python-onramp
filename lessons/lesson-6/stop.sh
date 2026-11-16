#!/usr/bin/env bash
# Stop the ShopStream API stack (exits 0 even if nothing runs). Add --wipe to delete the database volume too.
if [ "${1:-}" = "--wipe" ]; then V="-v"; else V=""; fi
docker compose -p shopstream-api down --remove-orphans $V 2>/dev/null && echo "[INFO] stack stopped" || echo "[INFO] nothing to stop"
exit 0
