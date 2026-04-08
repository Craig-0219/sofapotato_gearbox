-- ─────────────────────────────────────────────────────
-- HUD 顯示：檔位、轉速條、離合器、耐久警告
-- 每幀由獨立 DrawThread 呼叫
-- ─────────────────────────────────────────────────────

-- HUD 位置（螢幕比例座標）
local HUD_X        = 0.920   -- 右側
local HUD_Y        = 0.865   -- 下方
local RPM_BAR_W    = 0.080
local RPM_BAR_H    = 0.009
local CLUTCH_BAR_H = 0.040
local CLUTCH_BAR_W = 0.007

function DrawGearboxHUD()
    if not Config.HudEnabled then return end
    local state = GearboxState
    local cfg = GetActiveTransmissionConfig() or state.cfg
    if not state.inVehicle or not cfg then return end

    -- ── 檔位文字 ──────────────────────────────────────
    local gearText
    if state.isNeutral then
        gearText = 'N'
    elseif state.currentGear <= 0 then
        gearText = 'R'
    else
        gearText = tostring(state.currentGear)
    end

    local r, g, b = 255, 255, 255
    if state.isShifting then
        r, g, b = 255, 200, 50               -- 換檔中：橘黃
    elseif state.rpm > GearboxConst.Rpm.REDLINE then
        r, g, b = 255, 50, 50                -- 紅線：紅色
    elseif state.rpm > GearboxConst.Rpm.SHIFT_UP then
        r, g, b = 255, 140, 0               -- 建議升檔：橘
    end

    SetTextFont(4)
    SetTextScale(0.5, 0.068)
    SetTextColour(r, g, b, 255)
    SetTextJustification(0)
    SetTextWrap(0.0, 1.0)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(gearText)
    EndTextCommandDisplayText(HUD_X, HUD_Y)

    -- ── 轉速條 ────────────────────────────────────────
    local rpmX = HUD_X - 0.058
    local rpmY = HUD_Y + 0.015
    DrawRpmBar(state.rpm, rpmX, rpmY)

    -- ── 變速箱型號標籤 ────────────────────────────────
    SetTextFont(0)
    SetTextScale(0.5, 0.022)
    SetTextColour(200, 200, 200, 160)
    SetTextJustification(0)
    SetTextWrap(0.0, 1.0)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(cfg.label)
    EndTextCommandDisplayText(HUD_X, HUD_Y + 0.030)

    -- ── 離合器深度指示（MT 專用）──────────────────────
    if cfg.type == GearboxConst.Type.MT then
        DrawClutchBar(state.clutchValue, rpmX - 0.018, rpmY)
    end

    -- ── 離合器耐久警告 ────────────────────────────────
    if state.clutchHealth < GearboxConst.ClutchHealth.BAD then
        DrawBlinkText(GetLocale('ClutchWarn'), HUD_X, HUD_Y - 0.042, 255, 60, 60)
    end

    -- ── 溫度警告 ──────────────────────────────────────
    if Config.Temperature.enabled
        and state.gearboxTemp >= GearboxConst.Temp.HOT then
        local tr = math.floor(math.clamp(
            (state.gearboxTemp - GearboxConst.Temp.HOT)
            / (GearboxConst.Temp.OVERHEAT - GearboxConst.Temp.HOT) * 255,
            80, 255))
        DrawBlinkText(
            string.format('%.0f°C', state.gearboxTemp),
            HUD_X + 0.025, HUD_Y - 0.042,
            tr, math.max(0, 255 - tr), 0
        )
    end

    -- ── 起步控制指示器 ────────────────────────────────
    if state.launchPrepped then
        -- 就位：穩定綠色閃爍
        local pulse = math.floor(GetGameTimer() / 300) % 2
        if pulse == 0 then
            SetTextFont(4)
            SetTextScale(0.5, 0.030)
            SetTextColour(50, 255, 50, 255)
            SetTextJustification(0)
            SetTextWrap(0.0, 1.0)
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName('LC ●')
            EndTextCommandDisplayText(HUD_X, HUD_Y - 0.060)
        end
    elseif state.launchActive then
        -- 發射中：快速橘色閃爍
        local pulse = math.floor(GetGameTimer() / 150) % 2
        if pulse == 0 then
            SetTextFont(4)
            SetTextScale(0.5, 0.030)
            SetTextColour(255, 165, 0, 255)
            SetTextJustification(0)
            SetTextWrap(0.0, 1.0)
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName('🚀 LC')
            EndTextCommandDisplayText(HUD_X, HUD_Y - 0.060)
        end
    end
end

-- 轉速條（水平）
function DrawRpmBar(rpm, x, y)
    local fill = RPM_BAR_W * rpm

    -- 背景
    DrawRect(x + RPM_BAR_W * 0.5, y, RPM_BAR_W, RPM_BAR_H, 0, 0, 0, 140)

    -- 填充顏色依轉速
    local r, g, b = 60, 200, 60
    if rpm > 0.75 then r, g, b = 255, 160, 0 end
    if rpm > GearboxConst.Rpm.REDLINE then r, g, b = 255, 40, 40 end

    if fill > 0.0 then
        DrawRect(x + fill * 0.5, y, fill, RPM_BAR_H, r, g, b, 210)
    end
end

-- 離合器深度條（垂直）
function DrawClutchBar(clutch, x, y)
    local fill = CLUTCH_BAR_H * clutch
    local baseY = y + CLUTCH_BAR_H * 0.5

    DrawRect(x, baseY, CLUTCH_BAR_W, CLUTCH_BAR_H, 0, 0, 0, 120)
    if fill > 0.0 then
        DrawRect(x, baseY - (CLUTCH_BAR_H - fill) * 0.5, CLUTCH_BAR_W, fill,
            180, 180, 255, 200)
    end
end

-- 閃爍文字（每 500ms 閃一次）
function DrawBlinkText(text, x, y, r, g, b)
    local pulse = math.floor(GetGameTimer() / 500) % 2
    if pulse == 0 then return end

    SetTextFont(4)
    SetTextScale(0.5, 0.028)
    SetTextColour(r, g, b, 255)
    SetTextJustification(0)
    SetTextWrap(0.0, 1.0)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end
