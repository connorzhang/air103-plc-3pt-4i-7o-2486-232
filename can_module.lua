-- ===================== CAN 总线模块 =====================
-- 功能：火灾报警系统CAN总线通信模块
-- 作者：AI Assistant
-- 版本：1.0.0
-- 日期：2025-01-26

local can_module = {}

-- 模块配置参数
local config = {
    -- 基本配置
    can_dev_id = 0,                    -- CAN设备ID
    stb_pin = 27,                      -- STB引脚
    timing = {250000, 6, 6, 4, 2},     -- 时序配置：波特率, PTS, PBS1, PBS2, SJW
    
    -- 默认参数
    default_priority = 0,              -- 默认优先级
    default_device_type = 22,          -- 默认设备类型（点型离子感烟火灾探测器）
    default_event_type = 1,            -- 默认事件类型（火警）
    default_source_addr = 1,           -- 默认源地址
    
    -- FSKV键名
    source_addr_key = "can_source_addr",  -- 源地址存储键
    
    -- 发送配置
    tx_interval = 10000,               -- 发送间隔（毫秒）
    buffer_size = 8,                   -- 发送缓冲区大小
}

-- 内部变量
local is_enabled = false
local source_address = nil
local send_counter = 0
local tx_buf = nil

-- CAN ID组合函数
local function compose_can_id(priority, device_type, event_type, source_addr)
    -- 参数验证
    priority = priority or config.default_priority
    device_type = device_type or config.default_device_type
    event_type = event_type or config.default_event_type
    source_addr = source_addr or config.default_source_addr
    
    -- 直接计算29位ID
    local id_29 = (priority << 26) | (device_type << 18) | (event_type << 10) | (source_addr << 2) | 0
    
    -- 检查FSKV同步状态，实现自动同步
    local fskv_addr = nil
    local fskv_available = false
    pcall(function()
        fskv_addr = fskv.get(config.source_addr_key)
        fskv_available = true
    end)
    
    -- 如果FSKV可用且与当前源地址不同，自动同步
    if fskv_available and fskv_addr ~= nil and fskv_addr ~= source_address then
        log.info("can.id", "检测到FSKV源地址变化:", source_address, "->", fskv_addr)
        source_address = fskv_addr
        log.info("can.id", "源地址已自动同步到:", source_address)
    end
    
    log.info("can.id", "组合ID:", "优先级=", priority, "设备类型=", device_type, "事件类型=", event_type, "源地址=", source_addr)
    log.info("can.id", "源地址实际值:", source_addr, "类型:", type(source_addr))
    if fskv_available then
        log.info("can.id", "FSKV源地址:", fskv_addr, "类型:", type(fskv_addr), "是否同步:", source_addr == fskv_addr)
    else
        log.warn("can.id", "FSKV不可用，跳过同步检查")
    end
    log.info("can.id", "29位ID:", string.format("0x%08X", id_29))
    
    return id_29
end

-- 处理控制指令数据
local function process_control_command(data)
    if #data < 8 then
        log.warn("can.control", "控制指令数据长度不足:", #data)
        return false
    end
    
    local cmd_type = string.byte(data, 1)
    local target_device = string.byte(data, 2)
    local param1 = string.byte(data, 3)
    local param2 = string.byte(data, 4)
    local param3 = string.byte(data, 5)
    local param4 = string.byte(data, 6)
    local param5 = string.byte(data, 7)
    local checksum = string.byte(data, 8)
    
    log.info("can.control", "接收到控制指令:", "类型=", cmd_type, "目标设备=", target_device)
    log.info("can.control", "参数:", param1, param2, param3, param4, param5)
    
    -- 检查目标设备
    if target_device ~= 0xFF and target_device ~= source_address then
        log.info("can.control", "控制指令目标不是本设备，忽略")
        return false
    end
    
    -- 处理不同类型的控制指令
    if cmd_type == 0x01 then
        -- 设置节点ID指令
        local new_node_id = param1
        if new_node_id >= 1 and new_node_id <= 255 then
            log.info("can.control", "设置节点ID:", source_address, "->", new_node_id)
            
            -- 更新FSKV
            local fskv_success = false
            pcall(function()
                fskv.set(config.source_addr_key, new_node_id)
                fskv_success = true
            end)
            
            if fskv_success then
                source_address = new_node_id
                log.info("can.control", "节点ID已更新:", new_node_id, "并同步到FSKV")
                return true
            else
                log.error("can.control", "FSKV写入失败")
                return false
            end
        else
            log.error("can.control", "无效的节点ID:", new_node_id)
            return false
        end
        
    elseif cmd_type == 0x02 then
        -- 复位指令
        log.info("can.control", "执行复位指令")
        -- 这里可以添加复位逻辑
        return true
        
    elseif cmd_type == 0x03 then
        -- 自检指令
        log.info("can.control", "执行自检指令")
        -- 这里可以添加自检逻辑
        return true
        
    else
        log.warn("can.control", "未知的控制指令类型:", cmd_type)
        return false
    end
end

-- CAN回调函数
local function can_cb(dev_id, cb_type, param)
    log.info("can.cb", "回调触发:", "设备ID=", dev_id, "类型=", cb_type, "参数=", param)
    
    if cb_type == can.CB_MSG then
        -- 接收消息
        log.info("can.rx", "接收到CAN消息，开始读取...")
        local succ, rid, id_type, rtr, data = can.rx(dev_id)
        local msg_count = 0
        while succ do
            msg_count = msg_count + 1
            log.info("can.rx", "消息", msg_count, "ID:", mcu and mcu.x32 and mcu.x32(rid) or rid, "长度:", #data, "数据:", data:toHex())
            
            -- 解析接收到的CAN ID
            local priority = (rid >> 26) & 0x7
            local device_type = (rid >> 18) & 0xFF
            local event_type = (rid >> 10) & 0xFF
            local source_addr = (rid >> 2) & 0xFF
            
            log.info("can.parse", "接收ID解析:", "优先级=", priority, "设备类型=", device_type, "事件类型=", event_type, "源地址=", source_addr)
            
            -- 处理控制指令（事件类型8）
            if event_type == 8 then
                log.info("can.control", "接收到控制指令，开始处理")
                local success = process_control_command(data)
                if success then
                    log.info("can.control", "控制指令处理成功")
                else
                    log.warn("can.control", "控制指令处理失败")
                end
            end
            
            succ, rid, id_type, rtr, data = can.rx(dev_id)
        end
        log.info("can.rx", "消息读取完成，共处理", msg_count, "条消息")
    elseif cb_type == can.CB_TX then
        -- 发送结果
        log.info("can.tx", param and "发送成功" or "发送失败")
    elseif cb_type == can.CB_ERR then
        -- 错误信息
        log.info("can.err", mcu and mcu.x32 and mcu.x32(param) or param)
    elseif cb_type == can.CB_STATE then
        -- 状态变化
        log.info("can.state", param)
    end
end

-- 校验码计算函数
local function calculate_checksum(data)
    local checksum = 0
    for i = 1, #data - 1 do
        checksum = checksum ~ string.byte(data, i)
    end
    return checksum & 0xFF
end

-- 生成火警数据
local function generate_fire_data()
    local device_status = 0x02  -- 设备状态：报警
    local alarm_type = 0x01     -- 报警类型：烟感
    local alarm_level = 0x01    -- 报警级别：一级
    local timestamp = os.time() & 0xFFFF  -- 时间戳（低16位）
    local sensor_data = 0x1234  -- 传感器数据：烟浓度值
    local reserve = 0x00        -- 保留字段
    
    local data = string.char(
        device_status,
        alarm_type,
        alarm_level,
        (timestamp >> 8) & 0xFF,
        timestamp & 0xFF,
        (sensor_data >> 8) & 0xFF,
        sensor_data & 0xFF,
        0x00  -- 校验码占位
    )
    
    -- 计算校验码
    local checksum = calculate_checksum(data)
    data = string.sub(data, 1, 7) .. string.char(checksum)
    
    return data
end

-- 生成故障数据
local function generate_fault_data()
    local fault_code = 0x03     -- 故障代码：通信故障
    local fault_level = 0x02    -- 故障级别：严重
    local fault_time = os.time() & 0xFFFF  -- 故障时间（低16位）
    local device_id = source_address       -- 设备ID
    local status = 0x00         -- 状态：离线
    local reserve1 = 0x00       -- 保留字段1
    local reserve2 = 0x00       -- 保留字段2
    
    local data = string.char(
        fault_code,
        fault_level,
        (fault_time >> 8) & 0xFF,
        fault_time & 0xFF,
        device_id,
        status,
        reserve1,
        0x00  -- 校验码占位
    )
    
    -- 计算校验码
    local checksum = calculate_checksum(data)
    data = string.sub(data, 1, 7) .. string.char(checksum)
    
    return data
end

-- 生成状态数据
local function generate_status_data()
    local device_status = 0x01  -- 设备状态：正常
    local alarm_type = 0x00     -- 报警类型：无
    local alarm_level = 0x00    -- 报警级别：无
    local timestamp = os.time() & 0xFFFF  -- 时间戳（低16位）
    local sensor_data = 0x5678  -- 传感器数据：正常值
    local reserve = 0x00        -- 保留字段
    
    local data = string.char(
        device_status,
        alarm_type,
        alarm_level,
        (timestamp >> 8) & 0xFF,
        timestamp & 0xFF,
        (sensor_data >> 8) & 0xFF,
        sensor_data & 0xFF,
        0x00  -- 校验码占位
    )
    
    -- 计算校验码
    local checksum = calculate_checksum(data)
    data = string.sub(data, 1, 7) .. string.char(checksum)
    
    return data
end


-- 发送任务
local function can_tx_task()
    if not is_enabled then return end
    
    log.info("can.tx", "发送任务执行")
    send_counter = send_counter + 1
    if send_counter > 3 then send_counter = 1 end
    
    local data = nil
    local event_type = 0
    local description = ""
    
    -- 根据计数器发送不同类型的数据（移除控制指令）
    if send_counter == 1 then
        -- 发送火警数据
        data = generate_fire_data()
        event_type = 1  -- 火警
        description = "火警数据"
    elseif send_counter == 2 then
        -- 发送故障数据
        data = generate_fault_data()
        event_type = 2  -- 故障
        description = "故障数据"
    elseif send_counter == 3 then
        -- 发送状态数据
        data = generate_status_data()
        event_type = 4  -- 状态
        description = "状态数据"
    end
    
    if data then
        -- 使用组合函数生成发送ID
        local tx_id = compose_can_id(0, 22, event_type, source_address)
        
        log.info("can.tx", "发送", description, "ID:", string.format("0x%08X", tx_id), "数据:", data:toHex())
        
        -- 发送数据
        can.tx(config.can_dev_id, tx_id, can.EXT, false, true, data)
    end
end

-- 初始化CAN模块
function can_module.init()
    if not can then
        log.error("can.module", "CAN库不可用")
        return false
    end
    
    log.info("can.module", "初始化CAN模块")
    
    -- 从FSKV读取源地址（FSKV优先）
    local fskv_addr = nil
    local fskv_error = false
    pcall(function()
        fskv_addr = fskv.get(config.source_addr_key)
    end)
    
    if fskv_addr == nil then
        fskv_error = true
        log.info("can.init", "FSKV中无源地址，使用默认源地址:", config.default_source_addr)
        -- 将默认值写入FSKV
        source_address = config.default_source_addr
        pcall(function()
            fskv.set(config.source_addr_key, source_address)
            log.info("can.init", "默认源地址已写入FSKV")
        end)
    else
        source_address = fskv_addr
        log.info("can.init", "从FSKV读取源地址:", source_address)
    end
    
    log.info("can.init", "FSKV源地址:", fskv_addr, "默认源地址:", config.default_source_addr, "FSKV错误:", fskv_error)
    log.info("can.init", "最终源地址:", source_address, "类型:", type(source_address))
    
    -- 创建发送缓冲区
    tx_buf = zbuff.create(config.buffer_size)
    
    -- 配置STB引脚
    pcall(function()
        gpio.setup(config.stb_pin, 0)
    end)
    
    -- 初始化CAN（必须在设置mode之前完成所有配置）
    log.info("can.init", "开始初始化CAN...")
    can.init(config.can_dev_id, 128)
    log.info("can.init", "CAN初始化完成")
    
    can.on(config.can_dev_id, can_cb)
    log.info("can.init", "CAN回调已注册")
    
    can.timing(config.can_dev_id, config.timing[1], config.timing[2], config.timing[3], config.timing[4], config.timing[5])
    log.info("can.init", "CAN时序已设置:", config.timing[1], "bps")
    
    -- 设置过滤器（必须在设置mode之前）
    can.filter(0, false, 0x0, 0xFFFFFFFF)  -- 接收所有帧（标准帧和扩展帧）
    log.info("can.init", "过滤器已设置为接收所有帧")

    -- 最后设置模式（一旦设置就不能再修改其他配置）
    can.mode(config.can_dev_id, can.MODE_NORMAL)
    log.info("can.init", "CAN模式已设置为正常模式")
    
    -- 检查CAN状态
    local can_state = can.state(config.can_dev_id)
    log.info("can.init", "CAN当前状态:", can_state)
    
    is_enabled = true
    log.info("can.module", "CAN模块初始化完成，开始监听CAN消息...")
    
    -- 发送一条测试消息验证发送功能
    local test_data = zbuff.create(8)
    test_data:set(0, 0x01)
    test_data:set(1, 0x02)
    test_data:set(2, 0x03)
    test_data:set(3, 0x04)
    test_data:seek(4)
    
    local test_id = compose_can_id(0, 22, 1, source_address)
    can.tx(config.can_dev_id, test_id, can.EXT, false, true, test_data)
    log.info("can.init", "已发送测试消息，ID:", string.format("0x%08X", test_id))
    
    return true
end

-- 启动CAN模块
function can_module.start()
    if not is_enabled then
        log.error("can.module", "CAN模块未初始化")
        return false
    end
    
    log.info("can.module", "启动CAN模块")
    
    -- 启动周期发送任务
    sys.timerLoopStart(can_tx_task, config.tx_interval)
    
    log.info("can.module", "CAN模块启动完成")
    return true
end

-- 停止CAN模块
function can_module.stop()
    log.info("can.module", "停止CAN模块")
    
    is_enabled = false
    
    -- 停止定时器
    sys.timerStop(can_tx_task)
    
    -- 关闭CAN
    if can then
        can.mode(config.can_dev_id, can.MODE_BUSOFF)
    end
    
    log.info("can.module", "CAN模块已停止")
end

-- 发送自定义消息
function can_module.send(priority, device_type, event_type, source_addr, data)
    if not is_enabled then
        log.error("can.module", "CAN模块未启用")
        return false
    end
    
    local tx_id = compose_can_id(priority, device_type, event_type, source_addr or source_address)
    
    if data then
        can.tx(config.can_dev_id, tx_id, can.EXT, false, true, data)
    else
        tx_buf:set(0, send_counter)
        tx_buf:seek(send_counter)
        can.tx(config.can_dev_id, tx_id, can.EXT, false, true, tx_buf)
    end
    
    return true
end

-- 发送火警数据
function can_module.send_fire_alarm(priority, device_type, source_addr)
    if not is_enabled then
        log.error("can.module", "CAN模块未启用")
        return false
    end
    
    local data = generate_fire_data()
    local tx_id = compose_can_id(priority or 0, device_type or 22, 1, source_addr or source_address)
    
    log.info("can.fire", "发送火警数据", "ID:", string.format("0x%08X", tx_id), "数据:", data:toHex())
    can.tx(config.can_dev_id, tx_id, can.EXT, false, true, data)
    
    return true
end

-- 发送故障数据
function can_module.send_fault_report(priority, device_type, source_addr)
    if not is_enabled then
        log.error("can.module", "CAN模块未启用")
        return false
    end
    
    local data = generate_fault_data()
    local tx_id = compose_can_id(priority or 0, device_type or 22, 2, source_addr or source_address)
    
    log.info("can.fault", "发送故障数据", "ID:", string.format("0x%08X", tx_id), "数据:", data:toHex())
    can.tx(config.can_dev_id, tx_id, can.EXT, false, true, data)
    
    return true
end

-- 发送状态数据
function can_module.send_status_data(priority, device_type, source_addr)
    if not is_enabled then
        log.error("can.module", "CAN模块未启用")
        return false
    end
    
    local data = generate_status_data()
    local tx_id = compose_can_id(priority or 0, device_type or 22, 4, source_addr or source_address)
    
    log.info("can.status", "发送状态数据", "ID:", string.format("0x%08X", tx_id), "数据:", data:toHex())
    can.tx(config.can_dev_id, tx_id, can.EXT, false, true, data)
    
    return true
end

-- 发送控制指令（外部调用，用于配置其他设备）
function can_module.send_control_command(cmd_type, target_device, param1, param2, param3, param4, param5, priority, device_type)
    if not is_enabled then
        log.error("can.module", "CAN模块未启用")
        return false
    end
    
    -- 构建控制指令数据
    local data = string.char(
        cmd_type or 0x01,        -- 指令类型
        target_device or 0xFF,   -- 目标设备
        param1 or 0x00,          -- 参数1
        param2 or 0x00,          -- 参数2
        param3 or 0x00,          -- 参数3
        param4 or 0x00,          -- 参数4
        param5 or 0x00,          -- 参数5
        0x00  -- 校验码占位
    )
    
    -- 计算校验码
    local checksum = calculate_checksum(data)
    data = string.sub(data, 1, 7) .. string.char(checksum)
    
    local tx_id = compose_can_id(priority or 0, device_type or 22, 8, source_address)
    
    log.info("can.control", "发送控制指令", "ID:", string.format("0x%08X", tx_id), "数据:", data:toHex())
    can.tx(config.can_dev_id, tx_id, can.EXT, false, true, data)
    
    return true
end

-- 设置源地址（同时更新FSKV）
function can_module.set_source_addr(addr)
    log.info("can.module", "设置源地址:", addr, "类型:", type(addr))
    if addr and addr >= 0 and addr <= 255 then
        source_address = addr
        
        -- 尝试写入FSKV
        local fskv_success = false
        pcall(function()
            fskv.set(config.source_addr_key, addr)
            fskv_success = true
        end)
        
        if fskv_success then
            log.info("can.module", "源地址已设置为:", source_address, "类型:", type(source_address), "FSKV写入成功")
        else
            log.warn("can.module", "源地址已设置为:", source_address, "类型:", type(source_address), "但FSKV写入失败")
        end
        return true
    else
        log.error("can.module", "无效的源地址:", addr, "类型:", type(addr))
        return false
    end
end

-- 从FSKV同步源地址
function can_module.sync_from_fskv()
    local fskv_addr = nil
    local fskv_available = false
    
    pcall(function()
        fskv_addr = fskv.get(config.source_addr_key)
        fskv_available = true
    end)
    
    if fskv_available and fskv_addr ~= nil then
        if fskv_addr ~= source_address then
            log.info("can.sync", "从FSKV同步源地址:", source_address, "->", fskv_addr)
            source_address = fskv_addr
            return true
        else
            log.info("can.sync", "源地址已同步，无需更新")
            return true
        end
    else
        log.warn("can.sync", "FSKV不可用或为空，无法同步")
        return false
    end
end

-- 发送设置节点ID指令（便捷函数）
function can_module.set_node_id(target_device, new_node_id)
    log.info("can.control", "发送设置节点ID指令:", "目标设备=", target_device, "新节点ID=", new_node_id)
    
    if new_node_id < 1 or new_node_id > 255 then
        log.error("can.control", "无效的节点ID:", new_node_id)
        return false
    end
    
    return can_module.send_control_command(0x01, target_device, new_node_id, 0x00, 0x00, 0x00, 0x00)
end

-- 获取源地址
function can_module.get_source_addr()
    return source_address
end

-- 检查FSKV同步状态
function can_module.check_fskv_sync()
    local fskv_addr = nil
    local fskv_available = false
    
    -- 尝试读取FSKV
    pcall(function()
        fskv_addr = fskv.get(config.source_addr_key)
        fskv_available = true
    end)
    
    local is_synced = fskv_available and (source_address == fskv_addr)
    
    log.info("can.sync", "=== FSKV同步检查 ===")
    log.info("can.sync", "当前源地址:", source_address, "类型:", type(source_address))
    
    if fskv_available then
        log.info("can.sync", "FSKV源地址:", fskv_addr, "类型:", type(fskv_addr))
        log.info("can.sync", "同步状态:", is_synced and "已同步" or "未同步")
    else
        log.warn("can.sync", "FSKV不可用，无法进行同步检查")
        log.info("can.sync", "同步状态: 未知（FSKV不可用）")
    end
    
    if fskv_available and not is_synced then
        log.warn("can.sync", "警告: 源地址不同步!")
        log.warn("can.sync", "当前值:", source_address, "FSKV值:", fskv_addr)
        
        -- 尝试同步
        if fskv_addr then
            log.info("can.sync", "尝试同步到FSKV值:", fskv_addr)
            source_address = fskv_addr
        else
            log.info("can.sync", "FSKV为空，同步到默认值:", config.default_source_addr)
            source_address = config.default_source_addr
            
            -- 尝试写入FSKV
            local write_success = false
            pcall(function()
                fskv.set(config.source_addr_key, source_address)
                write_success = true
            end)
            
            if write_success then
                log.info("can.sync", "默认值已写入FSKV")
            else
                log.warn("can.sync", "FSKV写入失败")
            end
        end
    elseif fskv_available then
        log.info("can.sync", "源地址同步正常")
    end
    
    log.info("can.sync", "==================")
    return is_synced
end

-- 设置发送间隔
function can_module.set_tx_interval(interval)
    if interval and interval > 0 then
        config.tx_interval = interval
        log.info("can.module", "发送间隔已设置为:", interval, "ms")
        return true
    else
        log.error("can.module", "无效的发送间隔:", interval)
        return false
    end
end

-- 获取模块状态
function can_module.get_status()
    return {
        enabled = is_enabled,
        source_addr = source_address,
        source_addr_type = type(source_address),
        tx_interval = config.tx_interval,
        send_counter = send_counter
    }
end

-- 调试函数：显示详细状态
function can_module.debug_info()
    -- 获取FSKV中的源地址
    local fskv_addr = fskv.get(config.source_addr_key)
    
    log.info("can.debug", "=== CAN模块调试信息 ===")
    log.info("can.debug", "模块启用状态:", is_enabled)
    log.info("can.debug", "当前源地址:", source_address, "类型:", type(source_address))
    log.info("can.debug", "FSKV源地址:", fskv_addr, "类型:", type(fskv_addr))
    log.info("can.debug", "源地址同步状态:", source_address == fskv_addr)
    log.info("can.debug", "默认源地址:", config.default_source_addr)
    log.info("can.debug", "发送计数器:", send_counter)
    log.info("can.debug", "发送间隔:", config.tx_interval, "ms")
    log.info("can.debug", "设备类型:", config.default_device_type)
    log.info("can.debug", "事件类型:", config.default_event_type)
    
    -- 测试ID组合
    local test_id = compose_can_id(0, 22, 1, source_address)
    log.info("can.debug", "测试ID组合:", string.format("0x%08X", test_id))
    
    -- 同步检查
    if source_address ~= fskv_addr then
        log.warn("can.debug", "警告: 源地址不同步! 当前:", source_address, "FSKV:", fskv_addr)
    else
        log.info("can.debug", "源地址同步正常")
    end
    
    log.info("can.debug", "========================")
end

-- 模块配置接口
function can_module.set_config(new_config)
    for key, value in pairs(new_config) do
        if config[key] ~= nil then
            config[key] = value
            log.info("can.module", "配置已更新:", key, "=", value)
        end
    end
end

-- 获取模块配置
function can_module.get_config()
    return config
end

return can_module
