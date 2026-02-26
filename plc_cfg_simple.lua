-- plc_config_manager_simple.lua - 简化的PLC配置管理器
local plc_config_manager = {}
local _started = false

local sys = require("sys")
local plc_controller = require("plc_controller")

-- 配置文件路径
local CONFIG_FILE = "/plc_sequences.json"
local BACKUP_FILE = "/plc_sequences.bak"

-- 简化的配置数据结构
local CONFIG_DATA = {
    version = "1.3.0",
    system_name = "采样系统PLC",
    description = "基于AIR8000芯片的采样系统PLC控制",
    hardware_config = {
        relay_pins = {
            s0 = 32,  -- 采样泵
            s1 = 33,  -- 标定切换阀
            s2 = 20,  -- 原位标定切换阀
            s3 = 21   -- 超标报警输出
        }
    },
    control_sequences = {
        k1_sampling = {
            name = "K1采样控制",
            description = "启动/停止采样泵",
            type = "toggle",
            target = "s0"
        },
        k5_backflush = {
            name = "K5反吹控制", 
            description = "执行反吹操作",
            type = "sequence",
            duration_ms = 10000
        },
        k9_calibration = {
            name = "K9标定控制",
            description = "执行标定操作", 
            type = "sequence",
            duration_ms = 30000
        }
    },
    modbus_commands = {
        start_sampling = "01 06 00 0C 00 01 78 08",
        stop_sampling = "01 06 00 0C 00 00 B9 C8",
        start_backflush = "01 06 00 0D 00 01 69 C8",
        stop_backflush = "01 06 00 0D 00 00 A8 08",
        start_calibration = "01 06 00 0E 00 01 29 C8",
        stop_calibration = "01 06 00 0E 00 00 68 08"
    }
}

-- 从文件加载配置（简化版本）
function plc_config_manager.load_config()
    log.info("plc_config_manager", "加载简化配置")
    
    -- 直接使用内置配置，跳过文件解析
    log.info("plc_config_manager", "使用内置配置数据")
    
    -- 应用配置到PLC控制器
    plc_config_manager.apply_config()
    return true
end

-- 应用配置到PLC控制器
function plc_config_manager.apply_config()
    log.info("plc_config_manager", "应用配置到PLC控制器")
    
    -- 检查PLC控制器是否可用
    if not plc_controller then
        log.error("plc_config_manager", "PLC控制器不可用")
        return false
    end
    
    -- 获取可用序列
    local available = plc_controller.get_available_sequences()
    if available then
        log.info("plc_config_manager", "可用序列:", table.concat(available, ", "))
    end
    
    -- 应用硬件配置
    log.info("plc_config_manager", "硬件配置:", 
        "S0(采样泵)=", CONFIG_DATA.hardware_config.relay_pins.s0,
        "S1(标定切换阀)=", CONFIG_DATA.hardware_config.relay_pins.s1,
        "S2(原位标定切换阀)=", CONFIG_DATA.hardware_config.relay_pins.s2,
        "S3(超标报警)=", CONFIG_DATA.hardware_config.relay_pins.s3
    )
    
    -- 应用控制序列配置
    for name, seq in pairs(CONFIG_DATA.control_sequences) do
        log.info("plc_config_manager", "序列配置:", name, seq.name, seq.description)
    end
    
    -- 应用Modbus命令配置
    for name, cmd in pairs(CONFIG_DATA.modbus_commands) do
        log.info("plc_config_manager", "Modbus命令:", name, cmd)
    end
    
    log.info("plc_config_manager", "配置应用完成")
    return true
end

-- 保存配置到文件（简化版本）
function plc_config_manager.save_config()
    log.info("plc_config_manager", "保存配置（简化版本）")
    
    -- 创建简单的配置文件
    local config_str = plc_config_manager.config_to_string(CONFIG_DATA)
    
    local success, result = pcall(function()
        -- 保存到主配置文件
        local file = io.open(CONFIG_FILE, "w")
        if file then
            file:write(config_str)
            file:close()
            log.info("plc_config_manager", "配置保存成功")
            return true
        end
        return false
    end)
    
    if not success then
        log.error("plc_config_manager", "配置保存失败:", result)
        return false
    end
    
    return result
end

-- 配置转换为字符串（简化版本）
function plc_config_manager.config_to_string(config)
    local lines = {}
    table.insert(lines, "{")
    table.insert(lines, '  "system_name": "' .. config.system_name .. '",')
    table.insert(lines, '  "version": "' .. config.version .. '",')
    table.insert(lines, '  "description": "' .. config.description .. '",')
    table.insert(lines, '  "hardware_config": {')
    table.insert(lines, '    "relay_pins": {')
    for name, pin in pairs(config.hardware_config.relay_pins) do
        table.insert(lines, '      "' .. name .. '": ' .. pin .. ',')
    end
    table.insert(lines, '    }')
    table.insert(lines, '  }')
    table.insert(lines, "}")
    
    return table.concat(lines, "\n")
end

-- 获取配置数据
function plc_config_manager.get_config()
    return CONFIG_DATA
end

-- 启动配置管理器
function plc_config_manager.start()
    if _started then
        log.warn("plc_config_manager", "配置管理器已在运行")
        return
    end
    
    log.info("plc_config_manager", "启动简化配置管理器")
    
    -- 加载配置
    if plc_config_manager.load_config() then
        log.info("plc_config_manager", "配置加载成功")
    else
        log.warn("plc_config_manager", "配置加载失败，使用默认配置")
    end
    
    -- 保存配置到文件
    plc_config_manager.save_config()
    
    _started = true
    log.info("plc_config_manager", "简化配置管理器启动完成")
end

-- 停止配置管理器
function plc_config_manager.stop()
    if not _started then
        return
    end
    
    log.info("plc_config_manager", "停止配置管理器")
    _started = false
end

-- 检查运行状态
function plc_config_manager.is_running()
    return _started
end

return plc_config_manager
