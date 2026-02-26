-- plc_examples.lua - PLC编程示例
local plc_examples = {}

local plc_editor = require("plc_editor")
local plc_controller = require("plc_controller")

-- 示例1：简单的继电器控制
function plc_examples.simple_relay_control()
    log.info("plc_examples", "=== 示例1：简单继电器控制 ===")
    
    local seq_id = plc_editor.create_sequence("简单控制", "S0和S1交替开关")
    
    -- 添加步骤
    plc_editor.add_step(seq_id, "gpio_on", {pin = "s0", description = "打开S0"})
    plc_editor.add_step(seq_id, "delay_5s")
    plc_editor.add_step(seq_id, "gpio_off", {pin = "s0", description = "关闭S0"})
    plc_editor.add_step(seq_id, "gpio_on", {pin = "s1", description = "打开S1"})
    plc_editor.add_step(seq_id, "delay_5s")
    plc_editor.add_step(seq_id, "gpio_off", {pin = "s1", description = "关闭S1"})
    
    log.info("plc_examples", "创建序列完成，ID:", seq_id)
    return seq_id
end

-- 示例2：温度控制循环
function plc_examples.temperature_control_loop()
    log.info("plc_examples", "=== 示例2：温度控制循环 ===")
    
    local seq_id = plc_editor.create_sequence("温控循环", "根据温度自动控制加热循环")
    
    plc_editor.add_step(seq_id, "wait_k1")
    plc_editor.add_step(seq_id, "gpio_on", {pin = "s0", description = "启动加热"})
    plc_editor.add_step(seq_id, "delay_10s")
    plc_editor.add_step(seq_id, "gpio_off", {pin = "s0", description = "停止加热"})
    plc_editor.add_step(seq_id, "delay_5s")
    plc_editor.add_step(seq_id, "gpio_on", {pin = "s1", description = "启动冷却"})
    plc_editor.add_step(seq_id, "delay_3s")
    plc_editor.add_step(seq_id, "gpio_off", {pin = "s1", description = "停止冷却"})
    
    log.info("plc_examples", "创建温控序列完成，ID:", seq_id)
    return seq_id
end

-- 示例3：复杂工业流程
function plc_examples.industrial_process()
    log.info("plc_examples", "=== 示例3：复杂工业流程 ===")
    
    local seq_id = plc_editor.create_sequence("工业流程", "完整的工业控制流程")
    
    -- 启动阶段
    plc_editor.add_step(seq_id, "gpio_on", {pin = "s0", description = "启动主电源"})
    plc_editor.add_step(seq_id, "delay_2s")
    plc_editor.add_step(seq_id, "modbus_start")
    
    -- 预热阶段
    plc_editor.add_step(seq_id, "gpio_on", {pin = "s1", description = "启动预热"})
    plc_editor.add_step(seq_id, "delay_10s")
    plc_editor.add_step(seq_id, "gpio_off", {pin = "s1", description = "预热完成"})
    
    -- 主工作阶段
    plc_editor.add_step(seq_id, "gpio_on", {pin = "s2", description = "启动主工作"})
    plc_editor.add_step(seq_id, "delay_30s")
    
    -- 冷却阶段
    plc_editor.add_step(seq_id, "gpio_off", {pin = "s2", description = "停止主工作"})
    plc_editor.add_step(seq_id, "gpio_on", {pin = "s3", description = "启动冷却"})
    plc_editor.add_step(seq_id, "delay_15s")
    plc_editor.add_step(seq_id, "gpio_off", {pin = "s3", description = "冷却完成"})
    
    -- 清理阶段
    plc_editor.add_step(seq_id, "modbus_stop")
    plc_editor.add_step(seq_id, "gpio_off", {pin = "s0", description = "关闭主电源"})
    
    log.info("plc_examples", "创建工业流程序列完成，ID:", seq_id)
    return seq_id
end

-- 示例4：自定义参数序列
function plc_examples.custom_parameters()
    log.info("plc_examples", "=== 示例4：自定义参数序列 ===")
    
    local seq_id = plc_editor.create_sequence("自定义参数", "使用自定义参数的序列")
    
    -- 自定义GPIO控制
    plc_editor.add_step(seq_id, "gpio_on", {
        pin = "s4", 
        description = "打开S4继电器"
    })
    
    -- 自定义延时
    plc_editor.add_step(seq_id, "delay_1s", {
        duration = 3000,  -- 覆盖为3秒
        description = "延时3秒"
    })
    
    -- 自定义Modbus指令
    plc_editor.add_step(seq_id, "modbus_start", {
        command = "custom_command",
        description = "执行自定义指令"
    })
    
    log.info("plc_examples", "创建自定义参数序列完成，ID:", seq_id)
    return seq_id
end

-- 运行所有示例
function plc_examples.run_all_examples()
    log.info("plc_examples", "开始运行所有PLC编程示例...")
    
    -- 运行示例
    local seq1 = plc_examples.simple_relay_control()
    local seq2 = plc_examples.temperature_control_loop()
    local seq3 = plc_examples.industrial_process()
    local seq4 = plc_examples.custom_parameters()
    
    -- 显示所有序列
    log.info("plc_examples", "=== 所有创建的序列 ===")
    local sequences = plc_editor.get_sequences()
    for _, seq in ipairs(sequences) do
        log.info("plc_examples", string.format("序列%d: %s (%s步骤)", 
            seq.id, seq.name, seq.step_count))
    end
    
    -- 导出第一个序列的Lua代码作为示例
    if seq1 then
        log.info("plc_examples", "=== 序列1的Lua代码 ===")
        local code = plc_editor.export_lua(seq1)
        log.info("plc_examples", code)
    end
    
    log.info("plc_examples", "所有示例运行完成！")
end

-- 测试序列执行
function plc_examples.test_sequence_execution()
    log.info("plc_examples", "=== 测试序列执行 ===")
    
    -- 获取所有可用序列
    local available = plc_controller.get_available_sequences()
    log.info("plc_examples", "可用序列:", table.concat(available, ", "))
    
    -- 测试启动序列
    if #available > 0 then
        local test_seq = available[1]
        log.info("plc_examples", "测试启动序列:", test_seq)
        plc_controller.start_sequence(test_seq)
    end
end

return plc_examples
