-- switch_monitor.lua
-- 开关状态监测模块：通过ADC值检测K1-K8开关状态

local switch_monitor = {}

local sys = require("sys")

-- 开关ADC阈值配置（根据实际测试调整）
local SWITCH_THRESHOLDS = {
    -- ADC3: K1-K4
    adc3 = {
        k1 = {min = 2000, max = 2300, default = 2860},  -- K1按下: 2129
        k2 = {min = 1400, max = 1700, default = 2860},  -- K2按下: 1526
        k3 = {min = 900,  max = 1200, default = 2860},  -- K3按下: 1041
        k4 = {min = 500,  max = 800,  default = 2860}   -- K4按下: 642
    },
    -- ADC2: K5-K8
    adc2 = {
        k5 = {min = 2000, max = 2300, default = 2860},  -- K5按下: 2129
        k6 = {min = 1400, max = 1700, default = 2860},  -- K6按下: 1526
        k7 = {min = 900,  max = 1200, default = 2860},  -- K7按下: 1041
        k8 = {min = 500,  max = 800,  default = 2860}   -- K8按下: 642
    },
    -- ADC1: K9-K11
    adc1 = {
        k11 = {min = 2000, max = 2300, default = 2860}, -- K11按下: ~2130
        k10 = {min = 1400, max = 1700, default = 2860}, -- K10按下: ~1527
        k9  = {min = 900,  max = 1200, default = 2860}  -- K9按下: ~1043
    }
}

-- 全局变量：存储开关状态
_G.switch_states = {
    k1 = false, k2 = false, k3 = false, k4 = false,
    k5 = false, k6 = false, k7 = false, k8 = false,
    k9 = false, k10 = false, k11 = false
}

-- 防抖状态记录
local debounce_states = {
    k1 = {last_change = 0, stable_state = false},
    k2 = {last_change = 0, stable_state = false},
    k3 = {last_change = 0, stable_state = false},
    k4 = {last_change = 0, stable_state = false},
    k5 = {last_change = 0, stable_state = false},
    k6 = {last_change = 0, stable_state = false},
    k7 = {last_change = 0, stable_state = false},
    k8 = {last_change = 0, stable_state = false},
    k9 = {last_change = 0, stable_state = false},
    k10 = {last_change = 0, stable_state = false},
    k11 = {last_change = 0, stable_state = false}
}

-- 防抖时间（毫秒）
local DEBOUNCE_TIME = 10

-- 开关状态变化检测（带防抖）
local function detect_switch_state(adc_value, thresholds, adc_name)
    local ms_h, ms_l = mcu.ticks2(1)
    local current_time = ms_h * 1000000 + ms_l  -- 转换为毫秒
    
    for switch, config in pairs(thresholds) do
        local is_pressed = (adc_value >= config.min and adc_value <= config.max)
        local debounce_info = debounce_states[switch]
        local was_pressed = _G.switch_states[switch]
        
        -- 如果状态发生变化，记录时间
        if is_pressed ~= debounce_info.stable_state then
            debounce_info.last_change = current_time
            debounce_info.stable_state = is_pressed
        end
        
        -- 检查是否已经稳定了防抖时间
        if (current_time - debounce_info.last_change) >= DEBOUNCE_TIME then
            -- 防抖时间已过，检查最终状态是否与当前系统状态不同
            if is_pressed ~= was_pressed then
                _G.switch_states[switch] = is_pressed
                if is_pressed then
                    log.info("switch_monitor", string.upper(switch), "按下，ADC值:", adc_value, "ADC通道:", adc_name)
                else
                    log.info("switch_monitor", string.upper(switch), "释放，ADC值:", adc_value, "ADC通道:", adc_name)
                end
            end
        end
    end
end

-- 启动开关监测任务
-- adc3_id: ADC3通道号（K1-K4，默认3）
-- adc2_id: ADC2通道号（K5-K8，默认2）
-- adc1_id: ADC1通道号（K9-K11，可选，默认1）
-- interval_ms: 检测间隔（默认10ms，确保快速响应）
function switch_monitor.start(adc3_id, adc2_id, adc1_id, interval_ms)
    adc3_id = adc3_id or 3
    adc2_id = adc2_id or 2
    -- 兼容旧调用：第三个参数可能是 interval_ms
    if type(adc1_id) == "number" and type(interval_ms) ~= "number" and adc1_id and adc1_id > 10 then
        interval_ms = adc1_id
        adc1_id = nil
    end
    adc1_id = adc1_id or 1
    interval_ms = interval_ms or 10  -- 10ms检测间隔，配合10ms防抖
    
    log.info("switch_monitor", "启动开关监测，ADC3(K1-K4):", adc3_id, "ADC2(K5-K8):", adc2_id, "ADC1(K9-K11):", adc1_id, "检测间隔:", interval_ms, "ms", "防抖时间:", DEBOUNCE_TIME, "ms")
    
    -- 初始化ADC
    adc.open(adc3_id)
    adc.open(adc2_id)
    if adc1_id then adc.open(adc1_id) end
    
    sys.taskInit(function()
        while true do
            -- 读取ADC值
            local adc3_value = adc.get(adc3_id)
            local adc2_value = adc.get(adc2_id)
            local adc1_value = adc1_id and adc.get(adc1_id) or nil
            
            -- 检测开关状态（带防抖）
            detect_switch_state(adc3_value, SWITCH_THRESHOLDS.adc3, "ADC3")
            detect_switch_state(adc2_value, SWITCH_THRESHOLDS.adc2, "ADC2")
            if adc1_value then
                detect_switch_state(adc1_value, SWITCH_THRESHOLDS.adc1, "ADC1")
            end
            
            -- 调试信息（可选，注释掉可减少日志）
            -- log.info("switch_monitor", "ADC3:", adc3_value, "ADC2:", adc2_value, adc1_value and ("ADC1:"..adc1_value) or "")
            
            sys.wait(interval_ms)
        end
    end)
end

-- 获取开关状态
-- switch_name: 开关名称，如 "k1", "k2" 等
-- return: true表示按下，false表示释放
function switch_monitor.get_state(switch_name)
    return _G.switch_states[switch_name] or false
end

-- 获取所有开关状态
-- return: 包含所有开关状态的表
function switch_monitor.get_all_states()
    return _G.switch_states
end

-- 检查是否有开关被按下
-- return: true表示有开关按下，false表示所有开关都释放
function switch_monitor.any_pressed()
    for _, state in pairs(_G.switch_states) do
        if state then
            return true
        end
    end
    return false
end

-- 获取按下的开关列表
-- return: 按下的开关名称数组
function switch_monitor.get_pressed_switches()
    local pressed = {}
    for switch, state in pairs(_G.switch_states) do
        if state then
            table.insert(pressed, switch)
        end
    end
    return pressed
end

-- 打印当前开关状态
function switch_monitor.print_states()
    local states = {}
    for switch, state in pairs(_G.switch_states) do
        table.insert(states, string.upper(switch) .. ":" .. (state and "按下" or "释放"))
    end
    log.info("switch_monitor", "开关状态:", table.concat(states, " "))
end

-- 获取防抖信息（调试用）
-- return: 包含每个开关防抖时间记录的表
function switch_monitor.get_debounce_info()
    return debounce_states
end

return switch_monitor
