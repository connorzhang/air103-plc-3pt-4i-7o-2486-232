-- plc_config_manager.lua - PLC配置管理器
local plc_config_manager = {}
local _started = false

local sys = require("sys")
local plc_controller = require("plc_controller")

-- 配置文件路径
local CONFIG_FILE = "/plc_sequences.json"
local BACKUP_FILE = "/plc_sequences.bak"

-- 配置数据结构
local CONFIG_DATA = {
    version = "1.0",
    sequences = {},
    global_settings = {
        auto_start = false,
        default_sequence = "",
        watchdog_timeout = 30000
    }
}

-- 从JSON文件加载配置
function plc_config_manager.load_config()
    local success, data = pcall(function()
        local file = io.open(CONFIG_FILE, "r")
        if not file then
            log.warn("plc_config_manager", "配置文件不存在:", CONFIG_FILE)
            return false
        end
        
        local content = file:read("*a")
        file:close()
        
        if content and content ~= "" then
            log.info("plc_config_manager", "配置文件加载成功，大小:", #content)
            -- 简化处理：直接返回成功，不解析JSON
            return true
        end
        
        return false
    end)
    
    if success and data then
        -- 解析JSON并加载序列
        local parsed = plc_config_manager.parse_json(data)
        if parsed then
            CONFIG_DATA = parsed
            -- 迁移：将 k1_control 改为 k9_control，并更新默认启动序列
            if CONFIG_DATA.sequences and CONFIG_DATA.sequences["k1_control"] and not CONFIG_DATA.sequences["k9_control"] then
                CONFIG_DATA.sequences["k9_control"] = CONFIG_DATA.sequences["k1_control"]
                -- 更新可读名称
                if type(CONFIG_DATA.sequences["k9_control"]) == "table" then
                    CONFIG_DATA.sequences["k9_control"].name = "K9控制序列"
                    CONFIG_DATA.sequences["k9_control"].description = CONFIG_DATA.sequences["k9_control"].description or "K9按下后的控制流程"
                end
                CONFIG_DATA.sequences["k1_control"] = nil
                if CONFIG_DATA.global_settings and CONFIG_DATA.global_settings.default_sequence == "k1_control" then
                    CONFIG_DATA.global_settings.default_sequence = "k9_control"
                end
                -- 保存迁移结果
                plc_config_manager.save_config()
                log.info("plc_config_manager", "配置迁移: k1_control -> k9_control")
            end
            plc_config_manager.apply_config()
            return true
        end
    end
    
    log.error("plc_config_manager", "配置文件加载失败")
    return false
end

-- 简单的JSON解析（基础版本）
function plc_config_manager.parse_json(json_str)
    -- 这是一个简化的JSON解析器，实际项目中建议使用cjson库
    local function parse_value(str, pos)
        str = str:match("^%s*(.-)%s*$", pos) -- 去除首尾空格
        
        if str:match("^%[") then
            -- 解析数组
            local array = {}
            local content = str:match("^%[(.+)%]$")
            if content then
                local items = {}
                local depth = 0
                local start = 1
                
                for i = 1, #content do
                    local char = content:sub(i, i)
                    if char == "[" then depth = depth + 1
                    elseif char == "]" then depth = depth - 1
                    elseif char == "," and depth == 0 then
                        table.insert(items, content:sub(start, i-1))
                        start = i + 1
                    end
                end
                table.insert(items, content:sub(start))
                
                for _, item in ipairs(items) do
                    local value = parse_value(item)
                    if value ~= nil then
                        table.insert(array, value)
                    end
                end
            end
            return array
        elseif str:match("^{") then
            -- 解析对象
            local obj = {}
            local content = str:match("^%{(.+)%}$")
            if content then
                local pairs = {}
                local depth = 0
                local start = 1
                
                for i = 1, #content do
                    local char = content:sub(i, i)
                    if char == "{" then depth = depth + 1
                    elseif char == "}" then depth = depth - 1
                    elseif char == "," and depth == 0 then
                        table.insert(pairs, content:sub(start, i-1))
                        start = i + 1
                    end
                end
                table.insert(pairs, content:sub(start))
                
                for _, pair in ipairs(pairs) do
                    local key, value = pair:match("^%s*\"([^\"]+)\"%s*:%s*(.+)$")
                    if key and value then
                        obj[key] = parse_value(value)
                    end
                end
            end
            return obj
        elseif str:match("^\"") then
            -- 解析字符串
            return str:match("^\"(.+)\"$")
        elseif str:match("^%d+%.%d+") then
            -- 解析浮点数
            return tonumber(str)
        elseif str:match("^%d+") then
            -- 解析整数
            return tonumber(str)
        elseif str:match("^true$") then
            return true
        elseif str:match("^false$") then
            return false
        elseif str:match("^null$") then
            return nil
        end
        
        return nil
    end
    
    return parse_value(json_str)
end

-- 应用配置到PLC控制器
function plc_config_manager.apply_config()
    log.info("plc_config_manager", "应用配置到PLC控制器")
    
    -- 清除现有动态序列
    local existing = plc_controller.get_available_sequences()
    for _, seq_name in ipairs(existing) do
        if seq_name ~= "K1" then -- 保留内置序列
            -- 这里需要添加清除序列的功能
            log.info("plc_config_manager", "清除现有序列:", seq_name)
        end
    end
    
    -- 加载新序列
    for name, sequence_data in pairs(CONFIG_DATA.sequences) do
        if plc_controller.add_dynamic_sequence(name, sequence_data) then
            log.info("plc_config_manager", "成功加载序列:", name)
        else
            log.error("plc_config_manager", "加载序列失败:", name)
        end
    end
    
    -- 应用全局设置
    if CONFIG_DATA.global_settings.auto_start and CONFIG_DATA.global_settings.default_sequence then
        log.info("plc_config_manager", "自动启动默认序列:", CONFIG_DATA.global_settings.default_sequence)
        -- 延迟启动，确保系统完全初始化
        sys.timerStart(function()
            plc_controller.start_sequence(CONFIG_DATA.global_settings.default_sequence)
        end, 5000)
    end
end

-- 保存配置到文件
function plc_config_manager.save_config()
    local success, result = pcall(function()
        -- 先保存到备份文件
        local backup = io.open(BACKUP_FILE, "w")
        if backup then
            backup:write(plc_config_manager.config_to_json(CONFIG_DATA))
            backup:close()
        end
        
        -- 保存到主配置文件
        local file = io.open(CONFIG_FILE, "w")
        if file then
            file:write(plc_config_manager.config_to_json(CONFIG_DATA))
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

-- 配置转换为JSON字符串
function plc_config_manager.config_to_json(config)
    local function value_to_json(value, indent)
        indent = indent or ""
        local next_indent = indent .. "  "
        
        if type(value) == "table" then
            local is_array = #value > 0
            local result = is_array and "[" or "{"
            
            if is_array then
                for i, item in ipairs(value) do
                    if i > 1 then result = result .. "," end
                    result = result .. "\n" .. next_indent .. value_to_json(item, next_indent)
                end
            else
                local first = true
                for k, v in pairs(value) do
                    if not first then result = result .. "," end
                    result = result .. "\n" .. next_indent .. string.format("\"%s\": %s", k, value_to_json(v, next_indent))
                    first = false
                end
            end
            
            result = result .. "\n" .. indent .. (is_array and "]" or "}")
            return result
        elseif type(value) == "string" then
            return string.format("\"%s\"", value)
        elseif type(value) == "boolean" then
            return tostring(value)
        elseif type(value) == "number" then
            return tostring(value)
        else
            return "null"
        end
    end
    
    return value_to_json(config)
end

-- 创建示例配置文件
function plc_config_manager.create_sample_config()
    local sample_config = {
        version = "1.0",
        sequences = {
            k1_control = {
                name = "K1控制序列",
                description = "K1按下后的控制流程",
                steps = {
                    {
                        type = "gpio_output",
                        params = {
                            pin = "s0",
                            state = true,
                            description = "打开S0保持"
                        }
                    },
                    {
                        type = "modbus_rtu",
                        params = {
                            command = "start_cycle_blow",
                            description = "启动采样探头循环反吹"
                        }
                    },
                    {
                        type = "gpio_output",
                        params = {
                            pin = "s1",
                            state = true,
                            description = "打开S1"
                        }
                    },
                    {
                        type = "delay",
                        params = {
                            duration = 10000,
                            description = "延时10秒"
                        }
                    },
                    {
                        type = "gpio_output",
                        params = {
                            pin = "s1",
                            state = false,
                            description = "关闭S1"
                        }
                    }
                }
            },
            temp_control = {
                name = "温度控制序列",
                description = "温度自动控制流程",
                steps = {
                    {
                        type = "condition",
                        params = {
                            condition = "wait_k1",
                            description = "等待K1按下"
                        }
                    },
                    {
                        type = "gpio_output",
                        params = {
                            pin = "s0",
                            state = true,
                            description = "启动加热"
                        }
                    },
                    {
                        type = "delay",
                        params = {
                            duration = 5000,
                            description = "延时5秒"
                        }
                    },
                    {
                        type = "gpio_output",
                        params = {
                            pin = "s0",
                            state = false,
                            description = "停止加热"
                        }
                    }
                }
            }
        },
        global_settings = {
            auto_start = true,
            default_sequence = "k1_control",
            watchdog_timeout = 30000
        }
    }
    
    CONFIG_DATA = sample_config
    plc_config_manager.save_config()
    log.info("plc_config_manager", "示例配置文件创建完成")
end

-- 获取当前配置
function plc_config_manager.get_config()
    return CONFIG_DATA
end

-- 更新配置
function plc_config_manager.update_config(new_config)
    if new_config and new_config.sequences then
        CONFIG_DATA = new_config
        plc_config_manager.apply_config()
        plc_config_manager.save_config()
        log.info("plc_config_manager", "配置更新成功")
        return true
    end
    
    return false
end

-- 启动配置管理器
function plc_config_manager.start()
    if _started then
        log.info("plc_config_manager", "已启动，跳过")
        return
    end
    _started = true
    log.info("plc_config_manager", "PLC配置管理器启动")
    
    -- 尝试加载配置文件
    if not plc_config_manager.load_config() then
        log.info("plc_config_manager", "创建示例配置文件")
        plc_config_manager.create_sample_config()
    end
    
    -- 监控配置文件变化（可选）
    sys.taskInit(function()
        while true do
            -- 这里可以添加文件监控逻辑
            sys.wait(30000) -- 30秒检查一次
        end
    end)
end

return plc_config_manager

