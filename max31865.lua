--[[
@module max31865
@summary max31865 热电偶温度检测
@version 1.0
@date    2024.06.17
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
--注意:ads1115的配置需按照项目需求配置,您需要按照配置寄存器说明重新配置 ADS1115_CONF_HCMD 和 ADS1115_CONF_LCMD !!!
-- 用法实例
max31865 = require("max31865")

sys.taskInit(function()
    max31865_spi_device = spi.deviceSetup(1,pin.PB11,1,1,8,5*1000*1000,spi.MSB,1,0)
    max31865.init(max31865_spi_device,pin.PB18)
    while 1 do
        max31865.get()
        -- log.info("main", "temp: ", temp, "fault: ", fault)
        sys.wait(1000)
    end
end)
]] --[[
        REGISTER NAME           READ ADDRESS    WRITE ADDRESS   POR STATE   READ/WRITE
    Configuration                   00h             80h            00h         R/W
    RTD MSBs                        01h              —             00h          R
    RTD LSBs                        02h              —             00h          R
    High Fault Threshold MSB        03h             83h            FFh         R/W
    High Fault Threshold LSB        04h             84h            FFh         R/W
    Low Fault Threshold  MSB        05h             85h            00h         R/W
    Low Fault Threshold  LSB        06h             86h            00h         R/W
    Fault Status                    07h              —             00h          R
]] 
    local max31865 = {}

local sys = require "sys"
local cs_config = require "cs_config"

local cs_pin = 31
-- max31865.ONESHOT                    =   0x00    -- 单次转换模式
-- max31865.CONTINUOUS                 =   0x01    -- 自动转换模式

-- max31865.SAMPLE1                    =   0x00    -- 1个样品
-- max31865.SAMPLE2                    =   0x01    -- 2个样品
-- max31865.SAMPLE4                    =   0x02    -- 4个样品
-- max31865.SAMPLE8                    =   0x03    -- 8个样品
-- max31865.SAMPLE16                   =   0x04    -- 16个样品

max31865.WIRE2 = 0x02 -- 2线模式
max31865.WIRE3 = 0x03 -- 3线模式
max31865.WIRE4 = 0x04 -- 4线模式

local MAX31865_CONFIG_REG = 0x00 -- 配置寄存器
local MAX31865_RTD_MSB_REG = 0x01 --
local MAX31865_RTD_LSB_REG = 0x02 --
local MAX31865_HFTH_MSB_REG = 0x03 --
local MAX31865_HFTL_LSB_REG = 0x04 --
local MAX31865_LFTH_MSB_REG = 0x05 --
local MAX31865_LFTL_LSB_REG = 0x06 --
local MAX31865_FAULT_STATUS_REG = 0x07 --

local max31865_spi_device
local max31865_pin_ready
local max31865_conversion_mode
local max31865_sample_mode
local max31865_cs_list = {}

local function max31865_write_cmd(reg, data)
    gpio.set(cs_pin,0)
    sys.wait(5)
    -- log.info("max31865_write_cmd " .. (reg|0x80) .. " " .. data)
    max31865_spi_device:send({reg | 0x80, data})
    gpio.set(cs_pin,1)
    sys.wait(5)
end

local function max31865_read_cmd(reg)
    gpio.set(cs_pin,0)
    sys.wait(5)
    local data = max31865_spi_device:transfer(string.char(reg))
    -- log.info(data:toHex())
    gpio.set(cs_pin,1)
    sys.wait(5)
    -- log.info("max31865_read_cmd " .. reg .. " " .. data:toHex())
    return data:byte()
end

local function max31865_read_multiple_cmd(reg,num)
    gpio.set(cs_pin,0)
    -- sys.wait(10)
    local data = max31865_spi_device:transfer(string.char(reg),nil,2)
    local _,raw_value = pack.unpack(data, ">H")
    -- log.info(raw_value,data:toHex())
    gpio.set(cs_pin,1)
    -- sys.wait(20)
    -- log.info("max31865_read_cmd " .. reg .. " " .. data:toHex())
    return raw_value
end

local function max31865_wait_ready()
    while true do
        if gpio.get(max31865_pin_ready) == 0 then
            return
        end
        sys.wait(100)
    end
end

local function max31865_set_wires(wires)
    local config = max31865_read_cmd(MAX31865_CONFIG_REG)
    if wires == max31865.WIRE3 then
        config = config | 0x10
    else -- 2 or 4 wires
        config = config & (~0x10)
    end
    log.info(MAX31865_CONFIG_REG, config)
    max31865_write_cmd(MAX31865_CONFIG_REG, config)
end

function max31865.enablebias(enable)
    local config = max31865_read_cmd(MAX31865_CONFIG_REG)
    if enable then -- enable bias
        config = config | 0x80
    else -- disable bias
        config = config & (~0x80)
    end
    max31865_write_cmd(MAX31865_CONFIG_REG, config)
end

function max31865.autoconvert(enable)
    local config = max31865_read_cmd(MAX31865_CONFIG_REG)
    if enable then -- enable autoconvert
        config = config | 0x40
    else -- disable autoconvert
        config = config & (~0x40)
    end
    max31865_write_cmd(MAX31865_CONFIG_REG, config)
end

function max31865.clear_fault()
    local config = max31865_read_cmd(MAX31865_CONFIG_REG)
    config = config|0x02
    max31865_write_cmd(MAX31865_CONFIG_REG, config)

end

function max31865.read_fault()
    return max31865_read_cmd(MAX31865_FAULT_STATUS_REG)
end

function max31865.set_thresholds(lower, upper)
    max31865_write_cmd(MAX31865_LFTL_LSB_REG, 0x00)
    max31865_write_cmd(MAX31865_LFTH_MSB_REG, 0x00)
    max31865_write_cmd(MAX31865_HFTL_LSB_REG, 0xff)
    max31865_write_cmd(MAX31865_HFTH_MSB_REG, 0xff)
end

function max31865.read_config_for_cs(cs)
    local old = cs_pin
    cs_pin = cs
    local v = max31865_read_cmd(MAX31865_CONFIG_REG)
    cs_pin = old
    return v
end

function max31865.probe_cs(cs)
    local old = cs_pin
    cs_pin = cs
    gpio.set(cs,1)
    sys.wait(5)
    local hi = gpio.get(cs)
    gpio.set(cs,0)
    sys.wait(5)
    local lo = gpio.get(cs)
    local cfg = max31865_read_cmd(MAX31865_CONFIG_REG)
    local fault = max31865_read_cmd(MAX31865_FAULT_STATUS_REG)
    gpio.set(cs,1)
    cs_pin = old
    return hi, lo, cfg, fault
end

function max31865.diagnose_cs()
    local list = (#max31865_cs_list > 0) and max31865_cs_list or cs_config.get_pins()
    for _, cs in ipairs(list) do
        local hi, lo, cfg, fault = max31865.probe_cs(cs)
        log.info("max31865", "diag", cs, hi, lo, cfg, fault)
    end
end

function max31865.init(spi_device, wires, pin_ready, pins)
    if type(spi_device) ~= "userdata" then
        return
    end
    max31865_spi_device = spi_device
    if type(pins) == "table" then
        max31865_cs_list = pins
    else
        max31865_cs_list = cs_config.get_pins()
    end
    for i=1,#max31865_cs_list do
        cs_pin = max31865_cs_list[i]
        local cfg = max31865_read_cmd(MAX31865_CONFIG_REG)
        max31865_set_wires(wires or max31865.WIRE3)
        cfg = (cfg | 0x80 | 0x40) & (~0x20)
        max31865_write_cmd(MAX31865_CONFIG_REG, cfg)
        max31865.set_thresholds(0, 0xffff)
        max31865.clear_fault()
        sys.wait(5)
    end
    
end

-- 计算实际温度函数
function calculate_temperature(adc_value)
    -- 相应常数
    local RTD_A = 3.9083e-3
    local RTD_B = -5.775e-7

    -- 创建 2 ^ 15 的值作为参考
    local ref = 32768

    -- 计算电阻
    local rtd_resistance = adc_value * 400.0 / ref

    -- 计算温度（这里使用Callendar-Van Dusen方程）
    local temp = (-RTD_A + math.sqrt(RTD_A * RTD_A - 4 * RTD_B * (1 - rtd_resistance / 100))) / (2 * RTD_B)

    -- 检查负温度（列文法兹修正）
    if temp >= 0 then
        return temp
    else
        temp = (-RTD_A - math.sqrt(RTD_A * RTD_A - 4 * RTD_B * (1 - rtd_resistance / 100))) / (2 * RTD_B)
        return temp
    end
end

-- function calculate_temperature(adc_value)
--     local resistance = (adc_value * 400.0) / 32768.0;
    

--     local temperature = (resistance - 100.0) / 0.385;
    
--     return temperature;
-- end

-- function max31865.read_rtd()
--         gpio.set(12,0)
--     sys.wait(60)
--     max31865.clear_fault()
--     max31865.enablebias(true)
--     sys.wait(10)

--     local config = max31865_read_cmd(MAX31865_CONFIG_REG)

--     config = config | 0x02 -- 自动转化 0x20是单次转化
--     max31865_write_cmd(MAX31865_CONFIG_REG, config)
--     log.info(config)
--     sys.wait(60)

--     local msb = max31865_read_cmd(MAX31865_RTD_MSB_REG)
--     local lsb = max31865_read_cmd(MAX31865_RTD_LSB_REG)

--     -- 计算合并的值（16位整数）  
--     local rtd_raw_value = (msb * 256) + lsb -- 原始16位值  

--     -- 如果需要除以2（通常不需要，除非文档说明）  
--     local rtd_value = rtd_raw_value >> 1 -- 右移一位等同于除以2 

--     -- 输出结果
--     -- print("RTD Value:", rtd_value)
--     temp = ((rtd_value / 32) - 256)
--     r_pt = ((rtd_value * 400) / 32768)

--     -- 打印结果
--     print("计算电阻值:", r_pt)
--     -- print("Temperature (from temp variable):", temp)

--     temperature = 2.57 * r_pt - 257

--     -- 打印计算出的温度值
--     print("PT100温度:", string.format("%.2f", temperature) .. " ℃")

--     max31865.enablebias(true)

-- end

-- 初始化滤波器（可指定窗口大小）

local function create_median_filter(window_size)
    local buffer = {}
    return {
        update = function(new_val)
            -- 更新缓冲区
            table.insert(buffer, new_val)
            -- 删除最小值的逻辑
            if #buffer > (window_size or 8) then
                local min_index = 1
                for i = 2, #buffer-1 do  -- 保留最新值（最后一位）
                    if buffer[i] < buffer[min_index] then
                        min_index = i
                    end
                end
                table.remove(buffer, min_index)  -- 移除最小值
            end
            -- 处理空缓冲区（理论上不会触发）
            if #buffer == 0 then return new_val end

            -- 计算中位数
            local sorted = {}
            for i, v in ipairs(buffer) do sorted[i] = v end
            table.sort(sorted)
            -- log.info(json.encode(sorted,"2f"))
            local mid = math.ceil(#sorted / 2)
            if #sorted % 2 == 1 then
                return sorted[mid]
            else
                -- 确保mid-1 >= 1
                return (sorted[mid] + sorted[math.max(1, mid-1)]) / 2
            end
        end,
        reset = function() buffer = {} end
    }
end


-- 配置参数（可动态调整）
local cfg = {
    window_size = 20,      -- 滑动窗口大小（建议5-20）
    max_delta = 30.0,       -- 相邻采样最大允许温差(℃)
    init_samples = 1,      -- 启动验证所需连续采样数
    init_max_range = 10.0   -- 启动阶段最大允许波动范围(℃)
}

-- 运行时状态
local state = {
    data_window = {},
    init_buffer = {},
    init_phase = true,
    last_valid = nil
}

-- 中位值计算（辅助函数）
local function median(t)
    table.sort(t)
    return t[math.ceil(#t/2)]
end

-- 主滤波函数（直接处理wd参数）
function filter_value(wd)
    -- 启动验证阶段
    if state.init_phase then
        table.insert(state.init_buffer, 1, wd)
        if #state.init_buffer > cfg.init_samples then
            table.remove(state.init_buffer)
            
            -- 计算启动数据极差
            local min_val = math.min(unpack(state.init_buffer))
            local max_val = math.max(unpack(state.init_buffer))
            if (max_val - min_val) <= cfg.init_max_range then
                state.init_phase = false
                state.data_window = state.init_buffer
                state.last_valid = median(state.init_buffer)
            end
        end
        return wd -- 启动阶段不输出有效值
    end

    -- 限幅滤波
    if state.last_valid and math.abs(wd - state.last_valid) > cfg.max_delta then
        wd = state.last_valid
    end

    -- 更新滑动窗口
    table.insert(state.data_window, 1, wd)
    if #state.data_window > cfg.window_size then
        table.remove(state.data_window)
    end

    -- 计算移动平均
    local sum = 0
    for _, v in ipairs(state.data_window) do
        sum = sum + v
    end
    state.last_valid = sum / #state.data_window

    return state.last_valid
end



-- 初始化滤波器（窗口大小=5）
local filter = create_median_filter(8)

function max31865.temperature(cs)
    if cs then
        cs_pin = cs
    end
    local cfg = max31865_read_cmd(MAX31865_CONFIG_REG)
    if cfg == 0 then
        return nil
    end
    if (cfg & 0x80) == 0 or (cfg & 0x40) == 0 then
        cfg = (cfg | 0x80 | 0x40)
        max31865_write_cmd(MAX31865_CONFIG_REG, cfg)
        sys.wait(5)
    end
    local msb = max31865_read_cmd(MAX31865_RTD_MSB_REG)
    local lsb = max31865_read_cmd(MAX31865_RTD_LSB_REG)
    local faultstatus = max31865.read_fault()
    if faultstatus ~= 0 then
        max31865.clear_fault()
        local rtd_raw_value_fault = (msb * 256) + lsb
        -- log.info("max31865", "fault", cs_pin, string.format("0x%02X", faultstatus), rtd_raw_value_fault)
        return nil
    end
    local rtd_raw_value = (msb * 256) + lsb
    if rtd_raw_value == 0 or rtd_raw_value == 65535 then
        return nil
    end
    local rtd_value = rtd_raw_value >> 1
    local rtd_temp_value = calculate_temperature(rtd_value)
    if rtd_temp_value < -200 or rtd_temp_value > 850 then
        return nil
    end
    -- log.info("max31865", "ok", cs_pin, rtd_raw_value, string.format("%.4f", rtd_temp_value))
    return rtd_temp_value
end

return max31865
