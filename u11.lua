local u11 = {}
function u11.init1()

    local uartid = 11,
-- 初始化modbus_rtu
modbus_rtu.init({
    uartid = 11, -- 接收/发送数据的串口id
    baudrate = 9600, -- 波特率
    gpio_485 = 25, -- 转向GPIO编号
    tx_delay = 50000 -- 转向延迟时间，单位us
})
-- 定义modbus_rtu数据接收回调
local function on_modbus_rtu_receive(frame)
    log.info("modbus_rtu frame received:", json.encode(frame))
    
    if frame.fun == 0x03 then -- 功能码0x03表示读取保持寄存器
        local byte = frame.byte
        local payload = frame.payload
        log.info("modbus_rtu payload (hex):", payload:toHex())
        -- 示例使用
        -- local modbus_data = payload  -- 示例数据
        -- local data_type = "DCBA"  -- 示例数据类型
        -- local result = unpack_modbus_data(modbus_data, "uint")
        -- local result2 = unpack_modbus_data(modbus_data, "short")
        -- local result3 = unpack_modbus_data(modbus_data, "int")
        -- local result4 = unpack_modbus_data(modbus_data, "ushort")
        -- -- local result5 = unpack_modbus_data(modbus_data, "digital")
        -- print("解包结果:", result, result2, result3, result4)
        -- print("计数:", count)
        -- print("解包结果:ABCD", json.encode(result5))
        -- 解析数据(假设数据为16位寄存器值)
        local values_big = {} -- 大端序解析结果
        for i = 1, #payload, 2 do
            local msb = payload:byte(i)
            local lsb = payload:byte(i + 1)

            -- 大端序解析
            local result_big = (msb * 256) + lsb
            table.insert(values_big, result_big)
        end

        -- 输出大端序的解析结果
        log.info("输出大端序的解析结果:", table.concat(values_big, ", "))

        -- 第一个寄存器是湿度，第二个是温度，除以10以获取实际值
        if #values_big == 2 then
            log.info("测试同款485温湿度计")
            local humidity = values_big[1] / 10
            local temperature = values_big[2] / 10

            -- 打印湿度和温度
            log.info(string.format("湿度: %.1f%%", humidity))
            log.info(string.format("温度: %.1f°C", temperature))

        else
            log.info("用户自己的485下位机，共有" .. #values_big .. "组数据")
            for index, value in ipairs(values_big) do
                log.info(string.format("寄存器 %d: %d (大端序)", index, value))
            end

        end
    else
        log.info("功能码不是03")
    end
end

-- 设置modbus_rtu数据接收回调
modbus_rtu.set_receive_callback(uartid, on_modbus_rtu_receive)

local function send_modbus_rtu_command(count)
    local addr = 0x01 -- 设备地址,此处填客户自己的
    local fun = 0x03 -- 功能码（03为读取保持寄存器），此处填客户自己的
    -- local data = string.char(0x00, 0x00, 0x00, 0x02) -- 起始地址和寄存器数量(此处填客户自己的起始地址进而寄存器数量)
    -- log.info("串口发送收到的 count",count)
    -- 将 count 转换为两个字节表示起始地址
    local high_byte = math.floor(count / 256)
    local low_byte = count % 256
    local register_count_high = 0x00
    local register_count_low = 0x02

    local data = string.char(high_byte, low_byte, register_count_high, register_count_low)
    -- log.info("串口发送:",uartid, addr, fun, data:toHex())
    modbus_rtu.send_command(uartid, addr, fun, data) -- 只发送一次命令并等待响应处理
    -- modbus_rtu.send_command(1, addr, fun, data, 5000) -- 循环5S发送一次

end
sys.timerLoopStart(function()
    sys.publish("USER_MSG11", "DATA" .. count)
    count = count + 1
    if count >= 10 then
        count = 1
    end

    send_modbus_rtu_command(count)
end, 3000)
sys.taskInit(function()
    local res, data
    while true do
        res, data = sys.waitUntil("USER_MSG11")
        -- log.info(PROJECT, res, data)
    end
end)
sys.taskInit(function()
    sys.wait(5000)
    -- send_modbus_rtu_command()

end)
end
return u11