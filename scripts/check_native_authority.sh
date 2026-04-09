#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FORBIDDEN='SetVehicle(CurrentGear|NextGear|HighGear|CurrentRpm|HandlingFloat|HandlingInt|MaxSpeed|EngineTorqueMultiplier|GearRatio)'

# 允許直接寫 native 的核心輸出檔
ALLOW=(
  "client/core/native_adapter.lua"
  "client/core/gear_ratios.lua"
)

# 檢查主要運行路徑（feature/modules + compat）
TARGETS=(
  client/modules/input.lua
  client/modules/damage.lua
  client/modules/hud.lua
  client/modules/menu.lua
  client/modules/upgrade.lua
  client/core/compat.lua
  client/features/drift.lua
  client/features/launch_control.lua
  client/features/sounds.lua
)

violations=0
for f in "${TARGETS[@]}"; do
  if rg -n "$FORBIDDEN" "$f" >/dev/null 2>&1; then
    echo "[FAIL] forbidden drivetrain native write in $f"
    rg -n "$FORBIDDEN" "$f"
    violations=1
  fi
done

for f in "${ALLOW[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "[FAIL] allowlisted file missing: $f"
    violations=1
  fi
done

if [[ $violations -ne 0 ]]; then
  exit 1
fi

echo "[OK] drivetrain native authority check passed"
