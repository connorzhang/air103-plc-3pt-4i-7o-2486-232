-- plc_controller.lua - PLC控制程序
local plc_controller = {}
local sys = require("sys")

-- 时间工具：返回单调递增的微秒时间
local function now_us()
    local ms_h, ms_l = mcu.ticks2(1)
    return ms_h * 1000000 + ms_l
end

-- 硬件配置
local RELAY_PINS = {
    s0 = 32, s1 = 33, s2 = 20, s3 = 21, s4 = 16,
    s5 = 162, s6 = 164, s7 = 160, s8 = 3, s9 = 5
}

-- 系统状态
local SYSTEM_STATE = {
    IDLE = "IDLE",                    -- 空闲状态
    RUNNING = "RUNNING",              -- 运行状态（采样泵工作）
    BACKFLUSH = "BACKFLUSH",          -- 反吹状态
    CALIBRATION = "CALIBRATION",      -- 标定状态
    IN_SITU_CAL = "IN_SITU_CAL",     -- 原位标定状态
    COMBINED = "COMBINED",            -- 组合状态（采样泵+反吹）
    COMBINED_CAL = "COMBINED_CAL"    -- 组合状态（采样泵+标定）
}

-- 当前系统状态
local current_system_state = SYSTEM_STATE.IDLE

-- 功能状态
local sampling_pump_running = false   -- 采样泵状态
local backflush_running = false       -- 反吹状态
local calibration_running = false     -- 标定状态
local in_situ_cal_running = false    -- 原位标定状态

-- 定时器
local backflush_timer = nil
local calibration_timer = nil
local in_situ_cal_timer = nil
local state_check_timer = nil

-- Modbus RTU命令库
local MODBUS_COMMANDS = {
    start_sampling = {0x01, 0x06, 0x00, 0x0C, 0x00, 0x01, 0x78, 0x08},  -- 截止阀开启 - 启动采样
    stop_sampling = {0x01, 0x06, 0x00, 0x0C, 0x00, 0x00, 0xB9, 0xC8},   -- 截止阀关闭 - 停止采样
    start_backflush = {0x01, 0x06, 0x00, 0x0D, 0x00, 0x01, 0x69, 0xC8}, -- 反吹阀开启 - 开始反吹
    stop_backflush = {0x01, 0x06, 0x00, 0x0D, 0x00, 0x00, 0xA8, 0x08},  -- 反吹阀关闭 - 停止反吹
    start_calibration = {0x01, 0x06, 0x00, 0x0E, 0x00, 0x01, 0x29, 0xC8}, -- 标定阀开启 - 开始标定
    stop_calibration = {0x01, 0x06, 0x00, 0x0E, 0x00, 0x00, 0x68, 0x08},  -- 标定阀关闭 - 停止标定
    emergency_stop = {0x01, 0x06, 0x00, 0x0F, 0x00, 0x00, 0xF9, 0xC8}   -- 紧急停止 - 关闭所有阀门
}

-- 发送Modbus RTU命令（模拟实现，后续可替换为实际通信）
local function send_modbus_command(command_name)
    local command = MODBUS_COMMANDS[command_name]
    if command then
        local hex_str = ""
        for i, byte in ipairs(command) do
            hex_str = hex_str .. string.format("%02X ", byte)
        end
        log.info("plc_controller", "发送Modbus指令:", command_name, "数据:", hex_str:sub(1, -2))
        -- TODO: 实现实际的UART1 485通信
        return true
    else
        log.error("plc_controller", "未知的Modbus命令:", command_name)
        return false
    end
end

-- 启动采样泵
local function start_sampling_pump()
    if not sampling_pump_running then
        log.info("plc_controller", "启动采样泵")
        gpio.set(RELAY_PINS.s0, 1)  -- 打开S0（采样泵）
        sampling_pump_running = true
        log.info("plc_controller", "采样泵已启动")
        return true
    end
    return false
end

-- 停止采样泵
local function stop_sampling_pump()
    if sampling_pump_running then
        log.info("plc_controller", "停止采样泵")
        gpio.set(RELAY_PINS.s0, 0)  -- 关闭S0（采样泵）
        sampling_pump_running = false
        log.info("plc_controller", "采样泵已停止")
        return true
    end
    return false
end

-- 启动反吹
local function start_backflush()
    if not backflush_running then
        log.info("plc_controller", "开始反吹操作")
        backflush_running = true
        
        -- 发送反吹指令
        send_modbus_command("start_backflush")
        
        -- 设置反吹定时器（10秒后自动停止）
        backflush_timer = sys.timerStart(function()
            log.info("plc_controller", "反吹自动停止")
            stop_backflush()
        end, 10000)
        
        log.info("plc_controller", "反吹已启动")
        return true
    end
    return false
end

-- 停止反吹
local function stop_backflush()
    if backflush_running then
        log.info("plc_controller", "停止反吹")
        
        -- 停止定时器
        if backflush_timer then
            sys.timerStop(backflush_timer)
            backflush_timer = nil
        end
        
        -- 发送停止反吹指令
        send_modbus_command("stop_backflush")
        
        -- 重置状态
        backflush_running = false
        log.info("plc_controller", "反吹已停止")
        return true
    end
    return false
end

-- 启动标定
local function start_calibration()
    if not calibration_running then
        log.info("plc_controller", "开始标定操作")
        calibration_running = true
        
        -- 关闭采样泵
        stop_sampling_pump()
        
        -- 打开标定切换阀
        gpio.set(RELAY_PINS.s1, 1)  -- 打开S1（标定切换阀）
        
        -- 发送标定指令
        send_modbus_command("start_calibration")
        
        -- 设置标定定时器（30秒后自动停止）
        calibration_timer = sys.timerStart(function()
            log.info("plc_controller", "标定自动停止")
            stop_calibration()
        end, 30000)
        
        log.info("plc_controller", "标定已启动")
        return true
    end
    return false
end

-- 停止标定
local function stop_calibration()
    if calibration_running then
        log.info("plc_controller", "停止标定")
        
        -- 停止定时器
        if calibration_timer then
            sys.timerStop(calibration_timer)
            calibration_timer = nil
        end
        
        -- 发送停止标定指令
        send_modbus_command("stop_calibration")
        
        -- 关闭标定切换阀
        gpio.set(RELAY_PINS.s1, 0)  -- 关闭S1（标定切换阀）
        
        -- 重置状态
        calibration_running = false
        log.info("plc_controller", "标定已停止")
        return true
    end
    return false
end

-- 启动原位标定
local function start_in_situ_calibration()
    if not in_situ_cal_running then
        log.info("plc_controller", "开始原位标定操作")
        in_situ_cal_running = true
        
        -- 停止其他操作
        stop_backflush()
        stop_calibration()
        
        -- 关闭本地标定电磁阀，打开原位电磁阀
        gpio.set(RELAY_PINS.s1, 0)  -- 关闭S1（标定切换阀）
        gpio.set(RELAY_PINS.s2, 1)  -- 打开S2（原位标定切换阀）
        
        -- 启动采样泵
        start_sampling_pump()
        
        -- 发送截止阀开启指令
        send_modbus_command("start_sampling")
        
        log.info("plc_controller", "原位标定已启动")
        return true
    end
    return false
end

-- 停止原位标定
local function stop_in_situ_calibration()
    if in_situ_cal_running then
        log.info("plc_controller", "停止原位标定")
        
        -- 停止定时器
        if in_situ_cal_timer then
            sys.timerStop(in_situ_cal_timer)
            in_situ_cal_timer = nil
        end
        
        -- 关闭原位电磁阀
        gpio.set(RELAY_PINS.s2, 0)  -- 关闭S2（原位标定切换阀）
        
        -- 停止采样泵
        stop_sampling_pump()
        
        -- 发送截止阀关闭指令
        send_modbus_command("stop_sampling")
        
        -- 重置状态
        in_situ_cal_running = false
        log.info("plc_controller", "原位标定已停止")
        return true
    end
    return false
end

-- 更新系统状态
local function update_system_state()
    if in_situ_cal_running then
        current_system_state = SYSTEM_STATE.IN_SITU_CAL
    elseif calibration_running and sampling_pump_running then
        current_system_state = SYSTEM_STATE.COMBINED_CAL
    elseif backflush_running and sampling_pump_running then
        current_system_state = SYSTEM_STATE.COMBINED
    elseif calibration_running then
        current_system_state = SYSTEM_STATE.CALIBRATION
    elseif backflush_running then
        current_system_state = SYSTEM_STATE.BACKFLUSH
    elseif sampling_pump_running then
        current_system_state = SYSTEM_STATE.RUNNING
    else
        current_system_state = SYSTEM_STATE.IDLE
    end
end

-- 状态检查定时器回调（原位标定停止后延时5秒重新检测）
local function state_check_callback()
    log.info("plc_controller", "延时5秒后重新检测按钮状态")
    
    -- 获取当前按钮状态
    local k1_pressed = (_G.switch_states and _G.switch_states.k1) or false
    local k5_pressed = (_G.switch_states and _G.switch_states.k5) or false
    local k9_pressed = (_G.switch_states and _G.switch_states.k9) or false
    
    if k5_pressed and k9_pressed then
        -- 两个按钮都按下，重新启动原位标定
        log.info("plc_controller", "检测到K5+K9同时按下，重新启动原位标定")
        start_in_situ_calibration()
    elseif k5_pressed then
        -- 只有K5按下，启动反吹
        log.info("plc_controller", "检测到K5按下，启动反吹")
        start_backflush()
    elseif k9_pressed then
        -- 只有K9按下，启动标定
        log.info("plc_controller", "检测到K9按下，启动标定")
        start_calibration()
    end
    
    -- 检查K1状态，如果K1还在按下，重新启动采样泵
    if k1_pressed and not sampling_pump_running then
        log.info("plc_controller", "检测到K1仍在按下，重新启动采样泵")
        start_sampling_pump()
    end
    
    -- 清除定时器引用
    state_check_timer = nil
end

-- 紧急停止所有操作
local function emergency_stop()
    log.warn("plc_controller", "执行紧急停止")
    
    -- 发送紧急停止指令
    send_modbus_command("emergency_stop")
    
    -- 停止所有定时器
    if backflush_timer then
        sys.timerStop(backflush_timer)
        backflush_timer = nil
    end
    if calibration_timer then
        sys.timerStop(calibration_timer)
        calibration_timer = nil
    end
    if in_situ_cal_timer then
        sys.timerStop(in_situ_cal_timer)
        in_situ_cal_timer = nil
    end
    if state_check_timer then
        sys.timerStop(state_check_timer)
        state_check_timer = nil
    end
    
    -- 关闭所有继电器
    for name, pin in pairs(RELAY_PINS) do
        gpio.set(pin, 0)
    end
    
    -- 重置所有状态
    sampling_pump_running = false
    backflush_running = false
    calibration_running = false
    in_situ_cal_running = false
    current_system_state = SYSTEM_STATE.IDLE
    
    log.info("plc_controller", "紧急停止完成，所有操作已停止")
end

-- 主控制逻辑
function plc_controller.run()
    log.info("plc_controller", "PLC控制程序启动 - 新逻辑：K1采样泵，K5反吹，K9标定，K5+K9原位标定")
    
    -- 初始化GPIO
    for name, pin in pairs(RELAY_PINS) do
        gpio.setup(pin, 0)
        gpio.set(pin, 0)
    end
    
    -- 启动采样控制逻辑（K1）
    sys.taskInit(function()
        local last_k1 = false
        while true do
            -- 检查K1开关状态
            local cur_k1 = (_G.switch_states and _G.switch_states.k1) or false
            
            -- 检测K1按下（上升沿）
            if cur_k1 and not last_k1 then
                log.info("plc_controller", "检测到K1按下，启动采样泵")
                start_sampling_pump()
            end
            
            -- 检测K1松开（下降沿）
            if not cur_k1 and last_k1 then
                log.info("plc_controller", "检测到K1松开，停止采样泵")
                stop_sampling_pump()
            end
            
            last_k1 = cur_k1
            sys.wait(50)  -- 50ms检查间隔
        end
    end)
    
    -- 启动反吹和标定控制逻辑（K5, K9）
    sys.taskInit(function()
        local last_k5 = false
        local last_k9 = false
        while true do
            -- 检查K5和K9开关状态
            local cur_k5 = (_G.switch_states and _G.switch_states.k5) or false
            local cur_k9 = (_G.switch_states and _G.switch_states.k9) or false
            
            -- 检测原位标定（K5+K9同时按下）
            if cur_k5 and cur_k9 and (not last_k5 or not last_k9) then
                log.info("plc_controller", "检测到K5+K9同时按下，启动原位标定")
                start_in_situ_calibration()
            end
            
            -- 检测原位标定停止（松开其中一个按钮）
            if in_situ_cal_running and (not cur_k5 or not cur_k9) then
                log.info("plc_controller", "原位标定时松开按钮，停止原位标定")
                stop_in_situ_calibration()
                
                -- 延时5秒后重新检测按钮状态
                if not state_check_timer then
                    state_check_timer = sys.timerStart(state_check_callback, 5000)
                end
            end
            
            -- 检测K5独立按下（上升沿，且K9未按下）
            if cur_k5 and not last_k5 and not cur_k9 and not in_situ_cal_running then
                log.info("plc_controller", "检测到K5独立按下，启动反吹")
                start_backflush()
            end
            
            -- 检测K5松开（下降沿）
            if not cur_k5 and last_k5 and not in_situ_cal_running then
                log.info("plc_controller", "检测到K5松开，停止反吹")
                stop_backflush()
            end
            
            -- 检测K9独立按下（上升沿，且K5未按下）
            if cur_k9 and not last_k9 and not cur_k5 and not in_situ_cal_running then
                log.info("plc_controller", "检测到K9独立按下，启动标定")
                start_calibration()
            end
            
            -- 检测K9松开（下降沿）
            if not cur_k9 and last_k9 and not in_situ_cal_running then
                log.info("plc_controller", "检测到K9松开，停止标定")
                stop_calibration()
                
                -- 检查K1状态，如果K1还在按下，重新启动采样泵
                local k1_pressed = (_G.switch_states and _G.switch_states.k1) or false
                if k1_pressed then
                    log.info("plc_controller", "K1仍在按下，重新启动采样泵")
                    start_sampling_pump()
                end
            end
            
            last_k5 = cur_k5
            last_k9 = cur_k9
            
            -- 更新系统状态
            update_system_state()
            
            sys.wait(50)  -- 50ms检查间隔
        end
    end)
    
    -- 状态监控
    sys.taskInit(function()
        while true do
            -- log.info("plc_controller", "系统状态:", 
            --     "状态=", current_system_state,
            --     "采样泵=", sampling_pump_running and "运行" or "停止",
            --     "反吹=", backflush_running and "运行" or "停止",
            --     "标定=", calibration_running and "运行" or "停止",
            --     "原位标定=", in_situ_cal_running and "运行" or "停止"
            -- )
            sys.wait(2000)  -- 2秒打印一次状态
        end
    end)
end

-- 获取系统状态
function plc_controller.get_system_status()
    return {
        current_state = current_system_state,
        sampling_pump = sampling_pump_running,
        backflush = backflush_running,
        calibration = calibration_running,
        in_situ_calibration = in_situ_cal_running,
        message = "新逻辑：K1采样泵，K5反吹，K9标定，K5+K9原位标定，支持同时运行"
    }
end

-- 手动控制采样泵（用于测试）
function plc_controller.manual_start_sampling()
    return start_sampling_pump()
end

function plc_controller.manual_stop_sampling()
    return stop_sampling_pump()
end

-- 手动控制反吹（用于测试）
function plc_controller.manual_start_backflush()
    return start_backflush()
end

function plc_controller.manual_stop_backflush()
    return stop_backflush()
end

-- 手动控制标定（用于测试）
function plc_controller.manual_start_calibration()
    return start_calibration()
end

function plc_controller.manual_stop_calibration()
    return stop_calibration()
end

-- 手动控制原位标定（用于测试）
function plc_controller.manual_start_in_situ_calibration()
    return start_in_situ_calibration()
end

function plc_controller.manual_stop_in_situ_calibration()
    return stop_in_situ_calibration()
end

-- 紧急停止
function plc_controller.emergency_stop()
    emergency_stop()
end

-- 获取安全状态
function plc_controller.get_safety_status()
    return {
        can_start_sampling = true,  -- 采样泵可以随时启动
        can_start_backflush = not in_situ_cal_running,  -- 原位标定时不能启动反吹
        can_start_calibration = not in_situ_cal_running,  -- 原位标定时不能启动标定
        safety_locked = in_situ_cal_running  -- 原位标定时锁定其他操作
    }
end

-- 获取所有可用序列
function plc_controller.get_available_sequences()
    return {"K1", "K5", "K9", "K5+K9"}
end

-- 添加动态序列（兼容接口）
function plc_controller.add_dynamic_sequence(name, sequence_data)
    log.info("plc_controller", "添加动态序列:", name, "（当前版本不支持动态序列）")
    return false
end

-- 启动序列（兼容接口）
function plc_controller.start_sequence(sequence_name)
    log.info("plc_controller", "启动序列:", sequence_name, "（当前版本不支持动态序列）")
    return false
end

-- 停止序列（兼容接口）
function plc_controller.stop_sequence()
    log.info("plc_controller", "停止序列（当前版本不支持动态序列）")
    return false
end

-- 获取序列状态（兼容接口）
function plc_controller.get_sequence_status()
    return {running = false, message = "当前版本不支持动态序列"}
end

return plc_controller
