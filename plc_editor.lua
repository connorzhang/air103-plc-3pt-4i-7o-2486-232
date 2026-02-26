-- plc_editor.lua - PLC可视化编程编辑器
local plc_editor = {}

local sys = require("sys")

-- 步骤模板库
local STEP_TEMPLATES = {
    -- GPIO控制
    gpio_on = {
        name = "打开继电器",
        type = "gpio_output",
        params = { pin = "s0", state = true, description = "打开继电器" },
        icon = "🔌"
    },
    gpio_off = {
        name = "关闭继电器", 
        type = "gpio_output",
        params = { pin = "s0", state = false, description = "关闭继电器" },
        icon = "🔌"
    },
    
    -- 延时控制
    delay_1s = {
        name = "延时1秒",
        type = "delay", 
        params = { duration = 1000, description = "延时1秒" },
        icon = "⏱️"
    },
    delay_5s = {
        name = "延时5秒",
        type = "delay",
        params = { duration = 5000, description = "延时5秒" },
        icon = "⏱️"
    },
    delay_10s = {
        name = "延时10秒", 
        type = "delay",
        params = { duration = 10000, description = "延时10秒" },
        icon = "⏱️"
    },
    
    -- 通信控制
    modbus_start = {
        name = "启动循环反吹",
        type = "modbus_rtu",
        params = { command = "start_cycle_blow", description = "启动采样探头循环反吹" },
        icon = "📡"
    },
    modbus_stop = {
        name = "停止循环反吹",
        type = "modbus_rtu", 
        params = { command = "stop_cycle_blow", description = "停止采样探头循环反吹" },
        icon = "📡"
    },
    
    -- 条件判断
    wait_k1 = {
        name = "等待K1按下",
        type = "condition",
        params = { 
            condition = function() return (_G.switch_states and _G.switch_states.k1) or false end,
            description = "等待K1开关按下" 
        },
        icon = "⏳"
    },
    
    -- 循环控制
    loop_start = {
        name = "循环开始",
        type = "loop_start",
        params = { count = 3, description = "循环3次" },
        icon = "🔄"
    },
    loop_end = {
        name = "循环结束",
        type = "loop_end", 
        params = { description = "循环结束" },
        icon = "🔄"
    }
}

-- 序列存储
local SEQUENCES = {}

-- 创建新序列
function plc_editor.create_sequence(name, description)
    local sequence = {
        name = name or "新序列",
        description = description or "",
        steps = {},
        created_time = os.time(),
        modified_time = os.time()
    }
    
    table.insert(SEQUENCES, sequence)
    log.info("plc_editor", "创建新序列:", name)
    return #SEQUENCES
end

-- 添加步骤到序列
function plc_editor.add_step(sequence_id, step_type, custom_params)
    if not SEQUENCES[sequence_id] then
        log.error("plc_editor", "序列不存在:", sequence_id)
        return false
    end
    
    local template = STEP_TEMPLATES[step_type]
    if not template then
        log.error("plc_editor", "步骤模板不存在:", step_type)
        return false
    end
    
    -- 复制模板参数
    local step_params = {}
    for k, v in pairs(template.params) do
        step_params[k] = v
    end
    
    -- 应用自定义参数
    if custom_params then
        for k, v in pairs(custom_params) do
            step_params[k] = v
        end
    end
    
    local step = {
        type = template.type,
        params = step_params,
        executed = false,
        template_name = step_type
    }
    
    table.insert(SEQUENCES[sequence_id].steps, step)
    SEQUENCES[sequence_id].modified_time = os.time()
    
    log.info("plc_editor", "添加步骤到序列", sequence_id, ":", template.name)
    return true
end

-- 删除序列中的步骤
function plc_editor.remove_step(sequence_id, step_index)
    if not SEQUENCES[sequence_id] then return false end
    
    local sequence = SEQUENCES[sequence_id]
    if step_index >= 1 and step_index <= #sequence.steps then
        table.remove(sequence.steps, step_index)
        sequence.modified_time = os.time()
        log.info("plc_editor", "删除步骤", step_index, "从序列", sequence_id)
        return true
    end
    
    return false
end

-- 移动步骤位置
function plc_editor.move_step(sequence_id, from_index, to_index)
    if not SEQUENCES[sequence_id] then return false end
    
    local sequence = SEQUENCES[sequence_id]
    if from_index >= 1 and from_index <= #sequence.steps and
       to_index >= 1 and to_index <= #sequence.steps then
        
        local step = table.remove(sequence.steps, from_index)
        table.insert(sequence.steps, to_index, step)
        sequence.modified_time = os.time()
        
        log.info("plc_editor", "移动步骤从", from_index, "到", to_index)
        return true
    end
    
    return false
end

-- 获取序列列表
function plc_editor.get_sequences()
    local result = {}
    for i, seq in ipairs(SEQUENCES) do
        table.insert(result, {
            id = i,
            name = seq.name,
            description = seq.description,
            step_count = #seq.steps,
            created_time = seq.created_time,
            modified_time = seq.modified_time
        })
    end
    return result
end

-- 获取序列详情
function plc_editor.get_sequence(sequence_id)
    if not SEQUENCES[sequence_id] then return nil end
    
    local seq = SEQUENCES[sequence_id]
    local result = {
        id = sequence_id,
        name = seq.name,
        description = seq.description,
        steps = {},
        created_time = seq.created_time,
        modified_time = seq.modified_time
    }
    
    for i, step in ipairs(seq.steps) do
        table.insert(result.steps, {
            index = i,
            type = step.type,
            params = step.params,
            template_name = step.template_name
        })
    end
    
    return result
end

-- 获取可用步骤模板
function plc_editor.get_step_templates()
    local result = {}
    for name, template in pairs(STEP_TEMPLATES) do
        table.insert(result, {
            name = name,
            display_name = template.name,
            icon = template.icon,
            type = template.type,
            description = template.description or ""
        })
    end
    return result
end

-- 保存序列到文件
function plc_editor.save_sequence(sequence_id, filename)
    if not SEQUENCES[sequence_id] then return false end
    
    local sequence = SEQUENCES[sequence_id]
    local data = {
        name = sequence.name,
        description = sequence.description,
        steps = sequence.steps,
        created_time = sequence.created_time,
        modified_time = os.time()
    }
    
    -- 这里可以保存到SD卡或Flash
    log.info("plc_editor", "保存序列到文件:", filename)
    return true
end

-- 从文件加载序列
function plc_editor.load_sequence(filename)
    -- 这里可以从SD卡或Flash加载
    log.info("plc_editor", "从文件加载序列:", filename)
    return true
end

-- 快速创建常用序列
function plc_editor.create_quick_sequence(sequence_type)
    if sequence_type == "k1_cycle" then
        -- K1循环控制序列
        local seq_id = plc_editor.create_sequence("K1循环控制", "K1按下后S0保持，S1循环开关")
        
        plc_editor.add_step(seq_id, "gpio_on", {pin = "s0", description = "打开S0保持"})
        plc_editor.add_step(seq_id, "modbus_start")
        plc_editor.add_step(seq_id, "gpio_on", {pin = "s1", description = "打开S1"})
        plc_editor.add_step(seq_id, "delay_10s")
        plc_editor.add_step(seq_id, "gpio_off", {pin = "s1", description = "关闭S1"})
        
        log.info("plc_editor", "创建快速序列: K1循环控制")
        return seq_id
        
    elseif sequence_type == "temp_control" then
        -- 温度控制序列
        local seq_id = plc_editor.create_sequence("温度控制", "根据温度自动控制加热")
        
        plc_editor.add_step(seq_id, "wait_k1")
        plc_editor.add_step(seq_id, "gpio_on", {pin = "s0", description = "启动加热"})
        plc_editor.add_step(seq_id, "delay_5s")
        plc_editor.add_step(seq_id, "gpio_off", {pin = "s0", description = "停止加热"})
        
        log.info("plc_editor", "创建快速序列: 温度控制")
        return seq_id
    end
    
    return nil
end

-- 导出序列为Lua代码
function plc_editor.export_lua(sequence_id)
    if not SEQUENCES[sequence_id] then return nil end
    
    local sequence = SEQUENCES[sequence_id]
    local code = {}
    
    table.insert(code, "-- 序列: " .. sequence.name)
    table.insert(code, "-- 描述: " .. sequence.description)
    table.insert(code, "local SEQUENCE_" .. string.upper(sequence.name:gsub("[^%w]", "_")) .. " = {")
    table.insert(code, "    name = \"" .. sequence.name .. "\",")
    table.insert(code, "    steps = {")
    
    for i, step in ipairs(sequence.steps) do
        table.insert(code, "        -- 步骤" .. i .. ": " .. step.params.description)
        table.insert(code, "        create_step(STEP_TYPES." .. string.upper(step.type) .. ", {")
        
        for k, v in pairs(step.params) do
            if type(v) == "string" then
                table.insert(code, "            " .. k .. " = \"" .. v .. "\",")
            elseif type(v) == "boolean" then
                table.insert(code, "            " .. k .. " = " .. tostring(v) .. ",")
            else
                table.insert(code, "            " .. k .. " = " .. tostring(v) .. ",")
            end
        end
        
        table.insert(code, "        }),")
        table.insert(code, "")
    end
    
    table.insert(code, "    }")
    table.insert(code, "}")
    
    return table.concat(code, "\n")
end

-- 启动编辑器
function plc_editor.start()
    log.info("plc_editor", "PLC编辑器启动")
    
    -- 创建一些示例序列
    plc_editor.create_quick_sequence("k1_cycle")
    plc_editor.create_quick_sequence("temp_control")
    
    -- 显示帮助信息
    log.info("plc_editor", "=== PLC编辑器使用说明 ===")
    log.info("plc_editor", "1. 创建序列: plc_editor.create_sequence('名称', '描述')")
    log.info("plc_editor", "2. 添加步骤: plc_editor.add_step(序列ID, '步骤模板', {自定义参数})")
    log.info("plc_editor", "3. 查看序列: plc_editor.get_sequences()")
    log.info("plc_editor", "4. 导出代码: plc_editor.export_lua(序列ID)")
    log.info("plc_editor", "5. 快速序列: plc_editor.create_quick_sequence('k1_cycle')")
end

return plc_editor
