-- ═══════════════════════════════════════════════════════════════
-- client/core/native_adapter.lua
-- GTA Native 呼叫的唯一入口
--
-- 職責：
--   - 所有修改 GTA 狀態的 native 都在這裡呼叫
--   - 分類：INIT_TIME / SHIFT_TIME / STATE_CHANGE / PER_FRAME
--   - 加 safety check（vehicle valid、native 存在）
--   - 追蹤哪些 native 已被設定（防止重複設同一值）
--
-- 不負責：決定何時呼叫（由 gearbox_core、modes 決定）
-- 不應從這裡讀取 GearboxState 做決策
-- ═══════════════════════════════════════════════════════════════

GB = GB or {}
GB.Native = {}

-- ═══════════════════════════════════════════════════════════════
-- 工具函式
-- ═══════════════════════════════════════════════════════════════

local function VehicleValid(v)
    return v and v ~= 0 and DoesEntityExist(v)
end

-- ═══════════════════════════════════════════════════════════════
-- INIT_TIME：進車或換型號時呼叫，不應重複呼叫
-- ═══════════════════════════════════════════════════════════════

-- 設定最大檔數（改變後需 reset gear 到 1）
function GB.Native.SetDriveGears(vehicle, maxGear)
    if not VehicleValid(vehicle) then return end
    if type(SetVehicleHandlingInt) ~= 'function' then return end
    SetVehicleHandlingInt(vehicle, 'CHandlingData', 'nInitialDriveGears', maxGear)
end

-- 設定 highGear（控制 GTA torque curve 上限）
-- ATMT/MT：永遠設 maxGear，保留完整 torque 分佈
-- AT：設 scriptGear，防止 GTA 自行升超過腳本當前檔
function GB.Native.SetHighGear(vehicle, gear)
    if not VehicleValid(vehicle) then return end
    if type(SetVehicleHighGear) ~= 'function' then return end
    SetVehicleHighGear(vehicle, gear)
end

-- 設定基礎驅動力（依齒比縮放後的值）
function GB.Native.SetDriveForce(vehicle, force)
    if not VehicleValid(vehicle) then return end
    if type(SetVehicleHandlingFloat) ~= 'function' then return end
    if not force or force <= 0 then return end
    SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce', force)
end

-- ═══════════════════════════════════════════════════════════════
-- SHIFT_TIME：換檔瞬間呼叫（ExecuteShift 中）
-- ═══════════════════════════════════════════════════════════════

-- 告知 GTA 目前在哪一檔（AT: 換檔一次；ATMT/MT: 每幀強制同步）
function GB.Native.SetCurrentGear(vehicle, gear)
    if not VehicleValid(vehicle) then return end
    if type(SetVehicleCurrentGear) ~= 'function' then return end
    SetVehicleCurrentGear(vehicle, gear)
end

-- 設定下一目標檔（配合 SetCurrentGear 一起設，防止 GTA AT 自行選擇）
function GB.Native.SetNextGear(vehicle, gear)
    if not VehicleValid(vehicle) then return end
    if type(SetVehicleNextGear) ~= 'function' then return end
    SetVehicleNextGear(vehicle, gear)
end

-- 換檔後更新當前檔頂速（dirty flag 驅動，不在每幀呼叫）
-- IMPORTANT：只設 fInitialDriveMaxFlatVel，不設 SetVehicleMaxSpeed
--            SetVehicleMaxSpeed 只設一次為 maxGear 頂速（在 gear_ratios.lua ApplyToVehicle）
function GB.Native.SetGearSpeedLimit(vehicle, topSpeedMps)
    if not VehicleValid(vehicle) then return end
    if not topSpeedMps or topSpeedMps <= 0 then return end
    if type(SetVehicleHandlingFloat) ~= 'function' then return end
    SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel', topSpeedMps)
end

-- Rev Match：降檔前預調 RPM
-- 只在 revMatch 開啟且降檔時呼叫，不在主循環呼叫
function GB.Native.SetRpm(vehicle, rpm)
    if not VehicleValid(vehicle) then return end
    if type(SetVehicleCurrentRpm) ~= 'function' then return end
    SetVehicleCurrentRpm(vehicle, math.clamp(rpm, 0.0, 1.0))
end

-- ═══════════════════════════════════════════════════════════════
-- STATE_CHANGE：狀態切換時呼叫（clutch on/off、stall、engine start）
-- ═══════════════════════════════════════════════════════════════

-- 離合器切斷時設 driveForce = 0（模擬動力中斷）
-- 配合 torqueCut 一起用，兩者一致才能完整切斷
-- 只在狀態變化時呼叫（不每幀）
local _clutchForceCutActive = false
local _savedDriveForce      = nil

function GB.Native.CutDriveForce(vehicle, cut)
    if not VehicleValid(vehicle) then return end
    if cut == _clutchForceCutActive then return end  -- 狀態未變，跳過

    if cut then
        -- 記錄當前值再切斷
        if type(GetVehicleHandlingFloat) == 'function' then
            local current = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce')
            if current and current > 0 then
                _savedDriveForce = current
            end
        end
        if not _savedDriveForce then
            _savedDriveForce = GB.State._appliedDriveForce
        end
        if type(SetVehicleHandlingFloat) == 'function' then
            SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce', 0.0001)
        end
        _clutchForceCutActive = true
    else
        _clutchForceCutActive = false
        local force = _savedDriveForce or GB.State._appliedDriveForce
        _savedDriveForce = nil
        if force and force > 0 and type(SetVehicleHandlingFloat) == 'function' then
            SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce', force)
        end
    end
end

-- 引擎開關（熄火/啟動）
function GB.Native.SetEngineOn(vehicle, on)
    if not VehicleValid(vehicle) then return end
    SetVehicleEngineOn(vehicle, on, true, false)
end

-- ═══════════════════════════════════════════════════════════════
-- PER_FRAME：每幀可以呼叫的 native（必須保持低成本且穩定）
-- 以下只有 SetVehicleCurrentRpm、SetVehicleClutch、SetVehicleEngineTorqueMultiplier
-- 這三個被 GTA 每幀 reset，必須每幀維持
-- ═══════════════════════════════════════════════════════════════

-- ATMT/MT 每幀設 RPM（GTA 音效 + 驅動力依賴此值）
-- AT 模式：不呼叫此函式
function GB.Native.SyncRpm(vehicle, rpm)
    if not VehicleValid(vehicle) then return end
    if type(SetVehicleCurrentRpm) ~= 'function' then return end
    SetVehicleCurrentRpm(vehicle, math.clamp(rpm, 0.0, 1.0))
end

-- ATMT/MT 每幀強制同步 gear（防止 GTA AT 自行 override）
-- 必須搭配正確的 RPM 值，否則 GTA 的 AT 邏輯仍會嘗試覆蓋
function GB.Native.SyncGear(vehicle, gear)
    if not VehicleValid(vehicle) then return end
    if type(SetVehicleCurrentGear) ~= 'function' then return end
    if type(SetVehicleNextGear)    ~= 'function' then return end
    SetVehicleCurrentGear(vehicle, gear)
    SetVehicleNextGear(vehicle, gear)
end

-- 離合器切斷時每幀設 torque multiplier = 0
-- GTA 每幀 reset 為 1.0，必須每幀維持
-- 接合時呼叫一次 reset（設為 1.0），之後不需要每幀設
local _torqueCutActive = false

function GB.Native.SyncTorqueCut(vehicle, cut)
    if not VehicleValid(vehicle) then return end
    if type(SetVehicleEngineTorqueMultiplier) ~= 'function' then return end

    if cut then
        SetVehicleEngineTorqueMultiplier(vehicle, 0.0)
        _torqueCutActive = true
    elseif _torqueCutActive then
        SetVehicleEngineTorqueMultiplier(vehicle, 1.0)
        _torqueCutActive = false
    end
end

-- 離合器軸位同步（GTA native: 0.0 = 切斷, 1.0 = 接合）
-- clutchAxis 語義相反（1.0 = 踩到底 = 切斷），需轉換
function GB.Native.SyncClutch(vehicle, clutchAxis)
    if not VehicleValid(vehicle) then return end
    if type(SetVehicleClutch) ~= 'function' then return end
    local nativeClutch = 1.0 - math.clamp(clutchAxis, 0.0, 1.0)
    SetVehicleClutch(vehicle, nativeClutch)
end

-- AT 模式：同步 highGear = scriptGear（防止 GTA 升超過腳本當前檔）
-- 每次 AT 換檔後呼叫，不在主循環每幀呼叫
function GB.Native.SyncATHighGear(vehicle, scriptGear, maxGear)
    if not VehicleValid(vehicle) then return end
    if type(SetVehicleHighGear) ~= 'function' then return end
    -- AT 模式：highGear = scriptGear（防止 GTA AT 自行升超過腳本檔位）
    -- 不設成 maxGear 是因為 AT 腳本本身決定升檔時機，不讓 GTA 越俎代庖
    local hg = math.min(scriptGear, maxGear)
    SetVehicleHighGear(vehicle, hg)
end

-- ═══════════════════════════════════════════════════════════════
-- 工具：重設 native_adapter 的內部 state（離車時呼叫）
-- ═══════════════════════════════════════════════════════════════
function GB.Native.Reset()
    _clutchForceCutActive = false
    _savedDriveForce      = nil
    _torqueCutActive      = false
end
