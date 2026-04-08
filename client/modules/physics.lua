-- ─────────────────────────────────────────────────────
-- 物理模擬：轉速、引擎煞車、換檔頓挫、渦輪遲滯
-- ─────────────────────────────────────────────────────

local BRAKE_CTRL = 72
local ENGINE_BRAKE_COOLDOWN_MS = 250
local MPS_TO_MPH = 2.236936
local _wasBrakePressed = false
local _lastBrakeReleaseAt = 0
local _lastDebugGear = -1
local _lastDebugAt = 0

-- 每幀更新物理模擬
function UpdatePhysics(dt)
    local state   = GearboxState
    local vehicle = state.vehicle
    if not DoesEntityExist(vehicle) then return end

    local cfg      = GetActiveTransmissionConfig() or state.cfg
    local gear     = state.currentGear
    local speed    = GetEntitySpeed(vehicle)
    local speedMph = speed * MPS_TO_MPH
    local speedKmh = speed * 3.6   -- fInitialDriveMaxFlatVel 單位為 km/h
    -- 前向速度（排除 Z 軸分量）用於 RPM 公式：過顛簸/跳躍時 GetEntitySpeed 含 Z 速度 spike，
    -- 只取水平前向分量可有效抑制地形起伏造成的 RPM 瞬間抖動
    local vel         = GetEntityVelocity(vehicle)
    local fwd         = GetEntityForwardVector(vehicle)
    local speedFwdMps = math.max(0.0, vel.x * fwd.x + vel.y * fwd.y)
    local speedFwdKmh = speedFwdMps * 3.6
    local throttleInput = GetVehicleThrottleOffset(vehicle)
    local rawThrottle = GetControlNormal(0, 71)  -- 備援：直接讀鍵盤輸入，避免 GTA 靜止高檔位鎖死油門回報
    local throttle = math.max(0.0, throttleInput, rawThrottle)
    local reversing = IsVehicleReversingState(vehicle)
    local brakeOn = IsControlPressed(0, BRAKE_CTRL)

    if brakeOn then
        _wasBrakePressed = true
    elseif _wasBrakePressed then
        _wasBrakePressed = false
        _lastBrakeReleaseAt = GetGameTimer()
    end

    if reversing then
        ReleaseEngineBraking(vehicle)
        state.rpm          = GetVehicleCurrentRpm(vehicle)
        state.targetRpm    = state.rpm
        state.lastThrottle = throttle
        state.lastSpeed    = speed
        return
    end

    -- ── Handling 還原 + per-gear 硬性限速（所有類型均執行）──────────────────
    -- 必須在 AT 早返回之前執行，AT 模式也需要正確的每檔極速設定。
    -- 策略：依當前檔位齒比縮放 fInitialDriveMaxFlatVel = gearTopSpeed，
    --   讓 GTA 驅動力在各檔頂速自然衰減為 0；SetVehicleMaxSpeed 保留為過衝安全網。
    if not state.driveForceCutActive then
        local gearRatioH = cfg.gearRatios[gear] or 1.0
        local topRatioH  = cfg.gearRatios[cfg.maxGear] or gearRatioH
        local overridesH = state.handlingOverrides
        local backupH    = state.handlingBackup
        local baseDriveForceH = (type(overridesH) == 'table' and tonumber(overridesH.fInitialDriveForce))
            or (type(backupH) == 'table' and tonumber(backupH.driveForce))
        local baseTopSpeedKmhH = (type(overridesH) == 'table' and tonumber(overridesH.fInitialDriveMaxFlatVel))
            or (type(backupH) == 'table' and tonumber(backupH.maxFlatVel))
        if baseDriveForceH and baseDriveForceH > 0 then
            SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce', baseDriveForceH)
        end
        if baseTopSpeedKmhH and baseTopSpeedKmhH > 0 and gearRatioH > 0 then
            local gearTopSpeed_kmhH = baseTopSpeedKmhH * (topRatioH / gearRatioH)
            SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel',
                gearTopSpeed_kmhH / 3.6)
            if type(SetVehicleMaxSpeed) == 'function' then
                SetVehicleMaxSpeed(vehicle, gearTopSpeed_kmhH / 3.6)
            end
        end
        if Config.F8GearDebug then
            local now = GetGameTimer()
            local changed = gear ~= _lastDebugGear
            if changed or (gear >= 3 and (now - _lastDebugAt) >= 500) then
                _lastDebugGear = gear
                _lastDebugAt = now
                local actualKmh = GetEntitySpeed(vehicle) * 3.6
                local gearTopKmh = (baseTopSpeedKmhH and gearRatioH > 0)
                    and (baseTopSpeedKmhH * (topRatioH / gearRatioH)) or -1
                local gtaGear = type(GetVehicleCurrentGear) == 'function' and GetVehicleCurrentGear(vehicle) or -1
                local gtaRpm  = type(GetVehicleCurrentRpm)  == 'function' and GetVehicleCurrentRpm(vehicle)  or -1
                print(('[Gearbox][Physics] type=%s scriptGear=%d gtaGear=%d gtaRpm=%.3f gearTop=%.1fkm/h actual=%.1fkm/h thr=%.2f driveCut=%s shifting=%s base=%.1f gr=%.3f tr=%.3f'):format(
                    tostring(cfg.type), gear, gtaGear, gtaRpm, gearTopKmh, actualKmh,
                    throttle, tostring(state.driveForceCutActive), tostring(state.isShifting),
                    baseTopSpeedKmhH or -1, gearRatioH, topRatioH
                ))
            end
        end
    end

    -- ── AT 模式：直接讀 GTA 原生 RPM，不自行計算寫回 ──────
    -- 自行計算後 SetVehicleCurrentRpm 會造成循環反饋：
    --   GTA 讀我們寫入的低 RPM → 計算驅動力不足 → 車速被壓制
    --   → speedRpm 永遠上不去 → 永遠卡在低檔
    -- AT 模式讓 GTA 自己跑物理，我們只監聽 RPM 決定換檔時機。
    if cfg.type == GearboxConst.Type.AT then
        state.rpm       = GetVehicleCurrentRpm(vehicle)
        state.targetRpm = state.rpm
        -- 渦輪建壓更新（不寫回 RPM）
        if cfg.turbo == true then
            UpdateTurbo(state.isShifting, throttle, dt)
        end
        -- 不呼叫 SetVehicleCurrentRpm，讓 GTA 自然驅動
        -- 引擎煞車仍正常作用
        if Config.EngineBrakingStrength > 0.0 then
            ApplyEngineBraking(vehicle, gear, speed, throttle, cfg, brakeOn)
        else
            ReleaseEngineBraking(vehicle)
        end
        state.lastThrottle = throttle
        state.lastSpeed    = speed
        return
    end

    -- ── ATMT / MT 模式：自行計算目標轉速並寫回 GTA ──────
    -- GTA 在 script 強制鎖檔情況下 RPM 計算不準，必須自行計算後寫回。
    -- 換檔期間（isShifting）使用快速 lerp，自然產生升檔落轉 / 退檔補轉效果。

    if not state.engineOn then
        state.targetRpm = 0.0

    elseif state.isNeutral or state.clutchKeyDown then
        -- 離合器切斷 / 空檔：自由轉速（跟隨油門）
        local freeTarget = throttle > 0.05
            and (GearboxConst.Rpm.IDLE + throttle * 0.86)
            or  GearboxConst.Rpm.IDLE
        state.targetRpm = Lerp(state.targetRpm, freeTarget, 2.5 * dt)

    else
        -- 依速度 + 齒比反推理論轉速
        -- 使用基礎極速（overrides/backup），避免讀到動態縮放後的 GTA 值造成 RPM 公式偏移
        local baseTopSpeed = (type(state.handlingOverrides) == 'table' and tonumber(state.handlingOverrides.fInitialDriveMaxFlatVel))
            or (type(state.handlingBackup) == 'table' and tonumber(state.handlingBackup.maxFlatVel))
        local maxSpeed = (baseTopSpeed and baseTopSpeed > 0) and baseTopSpeed
            or GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel')
        if not maxSpeed or maxSpeed <= 0 then maxSpeed = 50.0 end

        local gearRatio = cfg.gearRatios[gear] or 1.0
        local topRatio  = cfg.gearRatios[cfg.maxGear] or 1.0

        local speedRpm = math.clamp(
            (speedFwdKmh * gearRatio) / (maxSpeed * topRatio) * GearboxConst.Rpm.REDLINE,
            GearboxConst.Rpm.IDLE, 0.98
        )

        local hasTurbo    = cfg.turbo == true
        local turboFactor = (hasTurbo and state.turboBoost) or 1.0
        local effectiveThr = throttle * (0.20 + turboFactor * 0.80)

        -- MT 模式：全油門 → throttleFloor 接近紅線，GTA 才能施加最大驅動力。
        -- speedRpm 公式在車速達 gearTopSpeed 時正好等於 REDLINE，使 GTA 力在頂速歸零。
        -- ATMT 模式：保持低 throttleFloor（0.30），避免讓 UpdateAT 誤判立即升檔
        --   （state.rpm 若等於 REDLINE 則立刻超過 upshiftRpm，造成停車即升檔）。
        local isMT = cfg.type == GearboxConst.Type.MT
        local throttleFloor = GearboxConst.Rpm.IDLE + effectiveThr *
            (isMT and (GearboxConst.Rpm.REDLINE - GearboxConst.Rpm.IDLE) or 0.30)
        -- 平滑目標轉速：不直接設定，用 lerp 過濾速度抖動（地形起伏、GTA 物理雜訊）
        -- 換檔期間使用快速 lerp（讓目標快速收斂到新齒比）；平時 10.0 約 100ms 響應
        local rawTarget = math.max(speedRpm, throttleFloor)
        local targetRate = state.isShifting
            and (cfg.revDropRate * 32.0)
            or  10.0
        state.targetRpm = Lerp(state.targetRpm, rawTarget, targetRate * dt)
    end

    -- ── 渦輪建壓更新（每幀）────────────────────────────
    if cfg.turbo == true then
        UpdateTurbo(state.isShifting, throttle, dt)
    end

    -- ── 轉速平滑移動 ──────────────────────────────────
    -- 換檔期間快速 lerp（升檔落轉 / 退檔補轉）；平時慢速跟隨
    local turboLerpFactor = (cfg.turbo == true)
        and (0.30 + state.turboBoost * 0.70)
        or  1.0
    local lerpRate = state.isShifting
        and (cfg.revDropRate * 32.0)  -- 換檔快速落轉：0.25×32=8.0（> 一般 4.0），避免換檔後 RPM 驟變
        or  (4.0 * turboLerpFactor)
    state.rpm = Lerp(state.rpm, state.targetRpm, lerpRate * dt)
    state.rpm = math.clamp(state.rpm, 0.0, 1.0)

    -- 寫回 GTA（驅動力與引擎音效依此數值）
    SetVehicleCurrentRpm(vehicle, state.rpm)

    -- ── 引擎煞車 ──────────────────────────────────────
    if Config.EngineBrakingStrength > 0.0 then
        ApplyEngineBraking(vehicle, gear, speed, throttle, cfg, brakeOn)
    else
        ReleaseEngineBraking(vehicle)
    end

    -- ── MT 換檔頓挫 ────────────────────────────────────
    if state.isShifting and cfg.type == GearboxConst.Type.MT then
        ApplyShiftJerk(vehicle, state.lastThrottle, GetEffectiveClutch())
    end

    -- ── 防熄火輔助：轉速極低時短暫補油防止 GTA 熄火 ───
    if state.antiStall and state.engineOn then
        local stallRpm = cfg.stallRpm or GearboxConst.Rpm.STALL
        if state.rpm < stallRpm + 0.03 then
            state.rpm = math.min(GearboxConst.Rpm.IDLE + 0.02, state.rpm + 0.02)
            SetVehicleCurrentRpm(vehicle, state.rpm)
        end
    end

    state.lastThrottle = throttle
    state.lastSpeed    = speed
end

function ReleaseEngineBraking(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    SetVehicleBrake(vehicle, 0.0)
end

-- 引擎煞車（鬆油門低檔時施加輕微煞車力）
function ApplyEngineBraking(vehicle, gear, speed, throttle, cfg, brakeOn)
    if gear <= 0 then
        ReleaseEngineBraking(vehicle)
        return
    end
    if brakeOn then
        ReleaseEngineBraking(vehicle)
        return
    end
    if IsVehicleReversingState(vehicle) then
        ReleaseEngineBraking(vehicle)
        return
    end
    if throttle > 0.05 then
        ReleaseEngineBraking(vehicle)
        return
    end
    if speed < 2.0 then
        ReleaseEngineBraking(vehicle)
        return
    end
    if GearboxState.isNeutral then
        ReleaseEngineBraking(vehicle)
        return
    end
    if GearboxState.clutchKeyDown then
        ReleaseEngineBraking(vehicle)
        return
    end
    if (GetGameTimer() - _lastBrakeReleaseAt) < ENGINE_BRAKE_COOLDOWN_MS then
        ReleaseEngineBraking(vehicle)
        return
    end

    local gearRatio = cfg.gearRatios[gear] or 1.0
    local topRatio  = cfg.gearRatios[cfg.maxGear] or 1.0

    -- 低檔齒比大 → 引擎煞車強
    local brakingNorm  = math.clamp(gearRatio / (topRatio * 3.5), 0.0, 1.0)
    local brakingForce = brakingNorm * Config.EngineBrakingStrength * 0.06
    local forward = GetEntityForwardVector(vehicle)

    -- 用拖曳力模擬收油減速，避免像真的踩住煞車一樣殘留
    ReleaseEngineBraking(vehicle)
    ApplyForceToEntity(
        vehicle, 5,
        -forward.x * brakingForce, -forward.y * brakingForce, 0.0,
        0.0, 0.0, 0.0,
        false, false, true, true, false
    )
end

-- 換檔頓挫（未鬆油門或離合器不足時換檔的衝擊力）
function ApplyShiftJerk(vehicle, throttle, clutch)
    if throttle < 0.20 then return end  -- 油門太小不頓挫
    if clutch > 0.65 then return end     -- 離合器有切斷則不頓挫

    local jerk = (throttle - 0.20) * (1.0 - clutch) * 0.45
    local fwd  = GetEntityForwardVector(vehicle)
    ApplyForceToEntity(
        vehicle, 5,
        -fwd.x * jerk, -fwd.y * jerk, 0.0,
        0.0, 0.0, 0.0,
        false, false, true, true, false
    )
end

-- 渦輪遲滯模擬
function UpdateTurbo(isShifting, throttle, dt)
    local state = GearboxState
    if isShifting or throttle < 0.10 then
        state.turboBoost = Lerp(state.turboBoost, 0.0, Config.Turbo.dropRate * dt)
    else
        state.turboBoost = Lerp(state.turboBoost, throttle, Config.Turbo.spoolRate * dt)
    end
    state.turboBoost = math.clamp(state.turboBoost, 0.0, 1.0)
end

-- 轉速匹配補油（降檔前呼叫，rev match assist）
function DoRevMatch(oldGear, newGear, cfg)
    if not GearboxState.revMatch then return end
    if newGear >= oldGear then return end  -- 只在降檔時才補油

    local oldRatio = cfg.gearRatios[oldGear] or 1.0
    local newRatio = cfg.gearRatios[newGear] or 1.0
    -- 將轉速預先拉到新檔接合後的目標值（避免降檔後轉速飆高頓挫）
    local matchedRpm = math.min(GearboxState.rpm * (newRatio / oldRatio) * 0.90, 0.92)
    SetVehicleCurrentRpm(GearboxState.vehicle, matchedRpm)
    GearboxState.rpm = matchedRpm
end
