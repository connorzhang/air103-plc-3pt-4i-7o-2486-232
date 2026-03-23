-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "PLC-7k-2485-232-4i"
VERSION = "1.0.1"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end
-- 波特率转换函数
local function bandchange(band)
    local band_table = {[0]=2400, [1]=4800, [2]=9600, [3]=19200, [4]=38400, [5]=57600, [6]=115200, [7]=230400, [8]=460800, [9]=921600, [10]=2000000}
    -- log.info("bandchange输入:", band, "类型:", type(band))
    local result = band_table[band] or 9600
    -- log.info("bandchange输出:", result)
    return result
end

-- 初始化响应表
if _G.rsptb == nil then
    _G.rsptb = {}
    -- 01/02 功能码：位图镜像，初始化 8 字节（1..8），默认 0
    rsptb[0x01] = {}
    rsptb[0x02] = {}
    for i = 0, 7 do rsptb[0x01][i] = 0x00 end
    for i = 0, 7 do rsptb[0x02][i] = 0x00 end
    -- 03/04 功能码：寄存器镜像，初始化 200 字节（索引 0..199），默认 0
    rsptb[0x03] = {}
    for i = 0, 199 do rsptb[0x03][i] = 0x00 end
    rsptb[0x04] = {}
    for i = 0, 199 do rsptb[0x04][i] = 0x00 end
end

fskv.init()
log.style(1)
log.info("main", "PLC-7k-2485-232-4i - 启动采样功能模式")
-- 初始化串口配置
if not fskv.get("u0") then
    log.info("u0没有")
    fskv.set("u0", {1, 2, 8, 0, 1})  -- {add, band, databit, crc, stop}
else
    log.info("u0有")
end

-- 加载串口配置
local u0_config = fskv.get("u0") or {1, 2, 8, 0, 1}  -- 获取完整配置，有默认值
_G.addr0 = u0_config[1] or 1  -- 设备地址 (add)
_G.band0 = bandchange(u0_config[2] or 9600)  -- 波特率 (band)
_G.databit0 = u0_config[3] or 8  -- 数据位 (databit)
_G.crc0 = u0_config[4] or 0  -- CRC校验 (crc)
_G.stop0 = u0_config[5] or 1  -- 停止位 (stop)

-- 高效的字节序转换函数
local function swap_bytes_zbuff(data_string, pattern)
    local buff = zbuff.create(4)
    buff:copy(0, data_string, 0, 4)
    local temp = zbuff.create(4)
    
    if pattern == "ABCD" then
        -- 不交换，直接返回
        return data_string
    elseif pattern == "DCBA" then
        -- 完全反转
        temp:copy(0, buff, 3, 1)
        temp:copy(1, buff, 2, 1)
        temp:copy(2, buff, 1, 1)
        temp:copy(3, buff, 0, 1)
    elseif pattern == "BADC" then
        -- 交换相邻对
        temp:copy(0, buff, 1, 1)
        temp:copy(1, buff, 0, 1)
        temp:copy(2, buff, 3, 1)
        temp:copy(3, buff, 2, 1)
    elseif pattern == "CDAB" then
        -- 交换前后两字节
        temp:copy(0, buff, 2, 1)
        temp:copy(1, buff, 3, 1)
        temp:copy(2, buff, 0, 1)
        temp:copy(3, buff, 1, 1)
    end
    
    return temp:toStr(0, 4)
end

function pack_modbus_data(value, data_type)
    local format
    local buff = zbuff.create(4)
    
    -- 根据数据类型确定打包格式和字节序
    if data_type == "char" then
        format = ">c"
        local value1 = math.floor(value + 0.5)
        log.info(value, value1)
        return pack.pack(format, value1)
    elseif data_type == "uchar" then
        format = ">b"
        local value1 = math.floor(value + 0.5)
        if value1 < 0 then value1 = 0 end
        log.info(value, value1)
        return pack.pack(format, value1)
    elseif data_type == "short" then
        format = ">h"
        local value1 = math.floor(value + 0.5)
        log.info(value, value1)
        return pack.pack(format, value1)
    elseif data_type == "ushort" then
        format = ">H"
        local value1 = math.floor(value + 0.5)
        if value1 < 0 then value1 = 0 end
        return pack.pack(format, value1)
    elseif data_type == "int" then
        format = ">i"
        local value1 = math.floor(value + 0.5)
        log.info(value, value1)
        local packed = pack.pack(format, value1)
        log.info(#packed, packed:toHex())
        return packed
    elseif data_type == "uint" then
        format = ">I"
        local value1 = math.floor(value + 0.5)
        if value1 < 0 then value1 = 0 end
        log.info(value, value1)
        return pack.pack(format, value1)
    elseif data_type == "ABCD" then
        -- 大端格式，保持原来的字节序
        buff:pack(">f", value)
        return buff:toStr(0, 4)
    elseif data_type == "DCBA" then
        -- 大端格式，直接使用
        buff:pack(">f", value)
        return buff:toStr(0, 4)
    elseif data_type == "BADC" then
        -- 大端格式打包后交换字节序
        buff:pack(">f", value)
        return swap_bytes_zbuff(buff:toStr(0, 4), "BADC")
    elseif data_type == "CDAB" then
        -- 大端格式打包后交换字节序
        buff:pack(">f", value)
        return swap_bytes_zbuff(buff:toStr(0, 4), "CDAB")
    elseif data_type == "digital" then
        local packed = 0
        for i, bit in ipairs(value) do
            packed = packed | (bit << (i-1))
        end
        return string.char(packed)
    else
        -- 默认ABCD格式，保持原来的大端格式
        buff:pack(">f", value)
        return buff:toStr(0, 4)
    end
end

--传入数值和类型存储到MODBUSRTU从机的地址，第一个参数是数值，第二个参数是数据类型（char、uchar、short、ushort、int、uint、ABCD、DCBA、BADC、CDAB），第三个参数是存入寄存器的起始位置，1开始
function store_to_rsptb(value, data_type,  start_byte)
    -- if not rsptb[tbl_key] then error("无效表键") end
    if start_byte < 1 then start_byte = 1 end
    
    local packed = pack_modbus_data(value, data_type)
    
    -- 存储到rsptb表
    for i = 1, #packed do
        local pos = start_byte + i - 2
        rsptb[0x03][pos] = packed:byte(i)
        rsptb[0x04][pos] = packed:byte(i)
    end
    return true
end

_G.pt100 = 0
local cs_config = require("cs_config")
local pins = cs_config.get_pins()
_G.p1 = pins[1]
_G.p2 = pins[2]
_G.p3 = pins[3]
gpio.setup(pins[1],1, gpio.PULLUP)
gpio.setup(pins[2],1, gpio.PULLUP)
gpio.setup(pins[3],1, gpio.PULLUP)
-- gpio.setup(31,1, gpio.PULLUP)
gpio.setup(30,1, gpio.PULLUP) --PT1
gpio.setup(29,1, gpio.PULLUP) --PT2
gpio.setup(28,1, gpio.PULLUP) --PT3

-- 串口动态配置与应用
local function get_baud(code)
    local bauds = {[0]=2400, [1]=4800, [2]=9600, [3]=19200, [4]=38400, [5]=57600, [6]=115200}
    return bauds[code] or 9600
end

function _G.apply_uart_config()
    local def = {baud_code=2, parity=0, stop=1} -- 9600, NONE, 1
    local u1_cfg = fskv.get("cfg_u1") or def
    local u2_cfg = fskv.get("cfg_u2") or def
    local u4_cfg = fskv.get("cfg_u4") or def
    
    -- Parity map: 0=NONE, 1=ODD, 2=EVEN
    -- Stop bit map: 1=1, 2=2
    uart.setup(1, get_baud(u1_cfg.baud_code), 8, u1_cfg.stop, u1_cfg.parity, uart.LSB, 1024, nil, 0, 2000)
    uart.setup(2, get_baud(u2_cfg.baud_code), 8, u2_cfg.stop, u2_cfg.parity, uart.LSB, 1024, 14, 0, 100)
    uart.setup(4, get_baud(u4_cfg.baud_code), 8, u4_cfg.stop, u4_cfg.parity, uart.LSB, 1024, 43, 0, 100)
    
    -- 初始化响应表中的串口配置寄存器 (Reg 100..108)
    -- Reg 100 对应 0x03/0x04 中的 start_byte = 100 * 2 = 200
    rsptb[0x03][200] = bit.rshift(u1_cfg.baud_code, 8); rsptb[0x03][201] = bit.band(u1_cfg.baud_code, 0xFF)
    rsptb[0x03][202] = bit.rshift(u1_cfg.parity, 8); rsptb[0x03][203] = bit.band(u1_cfg.parity, 0xFF)
    rsptb[0x03][204] = bit.rshift(u1_cfg.stop, 8); rsptb[0x03][205] = bit.band(u1_cfg.stop, 0xFF)
    
    rsptb[0x03][206] = bit.rshift(u2_cfg.baud_code, 8); rsptb[0x03][207] = bit.band(u2_cfg.baud_code, 0xFF)
    rsptb[0x03][208] = bit.rshift(u2_cfg.parity, 8); rsptb[0x03][209] = bit.band(u2_cfg.parity, 0xFF)
    rsptb[0x03][210] = bit.rshift(u2_cfg.stop, 8); rsptb[0x03][211] = bit.band(u2_cfg.stop, 0xFF)
    
    rsptb[0x03][212] = bit.rshift(u4_cfg.baud_code, 8); rsptb[0x03][213] = bit.band(u4_cfg.baud_code, 0xFF)
    rsptb[0x03][214] = bit.rshift(u4_cfg.parity, 8); rsptb[0x03][215] = bit.band(u4_cfg.parity, 0xFF)
    rsptb[0x03][216] = bit.rshift(u4_cfg.stop, 8); rsptb[0x03][217] = bit.band(u4_cfg.stop, 0xFF)
    
    for i = 200, 217 do rsptb[0x04][i] = rsptb[0x03][i] end
end

-- 统一处理 Modbus 写寄存器逻辑 (由各个串口模块调用)
function _G.handle_modbus_write(reg, val_or_data, is_multiple)
    local reg_end = reg
    if not is_multiple then
        local high = bit.rshift(val_or_data, 8)
        local low = bit.band(val_or_data, 0xFF)
        rsptb[0x03][reg * 2] = high
        rsptb[0x03][reg * 2 + 1] = low
        rsptb[0x04][reg * 2] = high
        rsptb[0x04][reg * 2 + 1] = low
    else
        local data = val_or_data
        local count = #data / 2
        reg_end = reg + count - 1
        for i = 1, #data do
            rsptb[0x03][reg * 2 + i - 1] = data:byte(i)
            rsptb[0x04][reg * 2 + i - 1] = data:byte(i)
        end
    end
    
    -- 检查是否写到了串口配置区域 (Reg 100~108)
    if not (reg > 108 or reg_end < 100) then
        local function r16(r) return bit.lshift(rsptb[0x03][r*2] or 0, 8) + (rsptb[0x03][r*2+1] or 0) end
        fskv.set("cfg_u1", {baud_code=r16(100), parity=r16(101), stop=r16(102)})
        fskv.set("cfg_u2", {baud_code=r16(103), parity=r16(104), stop=r16(105)})
        fskv.set("cfg_u4", {baud_code=r16(106), parity=r16(107), stop=r16(108)})
        _G.apply_uart_config()
    end
end

_G.apply_uart_config()
local u1 = require("u1")
local u2 = require("u2")
local u4 = require("u4")
-- local u3 = require("u3")
log.info(type(u1))
u1.init1()
log.info(type(u2))
u2.init1()
log.info(type(u4))
u4.init1()
-- log.info(type(u3))
-- u3.init1()

    -- log.info(type(u3))
    -- u3.init1()
-- --输入
-- gpio.setup(2,1, gpio.PULLUP)
-- gpio.setup(3,1, gpio.PULLUP)
-- gpio.setup(6,1, gpio.PULLUP)
-- gpio.setup(7,1, gpio.PULLUP)

--5路开关输出默认关闭
gpio.setup(8,0) --开关4 --采样泵
gpio.setup(9,0) --开关5 --标定阀
gpio.setup(10,0) --开关6 --原位标定阀
gpio.setup(11,0) --开关7 --预留PWM11
gpio.setup(5,0) --继电器 --报警输出

-- 按键配置函数
local function recompute_buttons()
    local s = (gpio.get(2) == 0)
    local c = (gpio.get(3) == 0)
    local m = (gpio.get(6) == 0)
    local b = (gpio.get(7) == 0)
    local pump, cal, insitu = 0, 0, 0
    if c and b then
        pump, insitu, cal = 1, 1, 0
    elseif c and (not b) then
        pump, insitu, cal = 0, 0, 1
    elseif s then
        pump, insitu, cal = 1, 0, 0
    else
        pump, insitu, cal = 0, 0, 0
    end
    gpio.set(8, pump)
    gpio.set(9, cal)
    gpio.set(10, insitu)
    if not rsptb[0x01] then rsptb[0x01] = {} end
    if not rsptb[0x02] then rsptb[0x02] = {} end
    local in_byte = (s and 1 or 0) | ((c and 1 or 0) << 1) | ((m and 1 or 0) << 2) | ((b and 1 or 0) << 3)
    local alarm_on = (gpio.get(5) == 1) and 1 or 0
    local out_byte = (pump & 1) | ((cal & 1) << 1) | ((insitu & 1) << 2) | (alarm_on << 3)
    rsptb[0x02][0] = in_byte
    rsptb[0x01][0] = out_byte
    pcall(store_to_rsptb, m and 1 or 0, "ushort", 25)
    log.info("按键联动", string.format(
        "时刻=%s 启动=%d 标定=%d 维护=%d 反吹=%d -> 泵=%d 标定阀=%d 原位阀=%d 维护标志=%d",
        os.date("%H:%M:%S"), s and 1 or 0, c and 1 or 0, m and 1 or 0, b and 1 or 0,
        pump, cal, insitu, m and 1 or 0
    ))
end
local _btn_recompute_pending = false
local function schedule_recompute()
    if _btn_recompute_pending then return end
    _btn_recompute_pending = true
    sys.taskInit(function()
        sys.wait(20)
        _btn_recompute_pending = false
        recompute_buttons()
    end)
end
gpio.setup(2, function(val) schedule_recompute() end, gpio.PULLUP, gpio.BOTH)
gpio.debounce(2, 30)
gpio.setup(3, function(val) schedule_recompute() end, gpio.PULLUP, gpio.BOTH)
gpio.debounce(3, 30)
gpio.setup(6, function(val) schedule_recompute() end, gpio.PULLUP, gpio.BOTH)
gpio.debounce(6, 30)
gpio.setup(7, function(val) schedule_recompute() end, gpio.PULLUP, gpio.BOTH)
gpio.debounce(7, 30)
recompute_buttons()


-- 加热输出PWM频率接口初始化
local pwm_freq = 5
pwm.open(32, pwm_freq, 0)
pwm.open(33, pwm_freq, 0)
pwm.open(34, pwm_freq, 0)

-- 加载模块

local temp_manager = require("temp_manager")
local PT = require("pt100_control")
-- local ble = require("ble_module")

-- 启动三路温度轮询模块（每100ms更新 pt1/pt2/pt3）
temp_manager.start({ id = 1, cpol = 1, cpha = 1, databits = 8, clock = 1 * 1000 * 1000 }, { _G.p1, _G.p2, _G.p3 }, 10)
-- ble.start()

-- 输入改为中断模式，已取消轮询

-- 示例：主程序使用全局变量做温控（占位）
sys.taskInit(function()
    while 1 do
        -- if _G.pt1 and _G.pt2 and _G.pt3 then
            -- 在此处根据三路温度做温控逻辑
            log.info("温控输入", os.date("%Y-%m-%d %H:%M:%S"), string.format(
                "pt=[%.2f,%.2f,%.2f] duty=[%d,%d,%d] target=[%.1f,%.1f,%.1f]",
                _G.pt1 or 999, _G.pt2 or 999, _G.pt3 or 999,
                _G.d1 or 0, _G.d2 or 0, _G.d3 or 0,
                _G.tg1 or 0, _G.tg2 or 0, _G.tg3 or 0
            ))
            
            -- 显示开关状态
            -- local pressed_switches = switch_monitor.get_pressed_switches()
            -- if #pressed_switches > 0 then
            --     log.info("开关状态", "按下的开关:", table.concat(pressed_switches, ", "))
            -- end
        -- end
        sys.wait(1000)
    end
end)

local c1 = PT.new({control_cycle_ms=100, max_duty=90})
local c2 = PT.new({control_cycle_ms=100, max_duty=90})
local c3 = PT.new({control_cycle_ms=100, max_duty=90})
local c3_sw = PT.new({control_cycle_ms=100, max_duty=90})
sys.taskInit(function()
    while 1 do
        local t1 = _G.pt1
        local t2 = _G.pt2
        local t3 = _G.pt3
        local d1,d2,d3 = 0,0,0
        local d3s = 0
        local duty1, err1, p1, i1, dterm1, out1
        local duty2, err2, p2, i2, dterm2, out2
        local duty3, err3, p3, i3, dterm3, out3
        local duty3_sw, err3_sw, p3_sw, i3_sw, dterm3_sw, out3_sw
        if type(t1) == "number" and t1 ~= 999 then duty1, err1, p1, i1, dterm1, out1 = c1.step(t1); d1 = duty1 end
        if type(t2) == "number" and t2 ~= 999 then duty2, err2, p2, i2, dterm2, out2 = c2.step(t2); d2 = duty2 end
        if type(t3) == "number" and t3 ~= 999 then duty3, err3, p3, i3, dterm3, out3 = c3.step(t3); d3 = duty3 end
        if type(t3) == "number" and t3 ~= 999 then duty3_sw, err3_sw, p3_sw, i3_sw, dterm3_sw, out3_sw = c3_sw.step(t3); d3s = duty3_sw end
        _G.d1, _G.d2, _G.d3 = d1, d2, d3
        _G.tg1, _G.tg2, _G.tg3 = c1.get_target(), c2.get_target(), c3.get_target()
        _G.d3_sw = d3s
        -- log.info(pwm_freq,d1)
        pwm.open(32, pwm_freq, d1, 0, 100)
        pwm.open(33, pwm_freq, d2, 0, 100)
        pwm.open(34, pwm_freq, d3, 0, 100)
        sys.wait(100)
    end
end)

sys.taskInit(function()
    local window_ms = 2000
    local slice_ms = 100
    local counter = 0
    while 1 do
        local d = _G.d3_sw or 0
        if d < 0 then d = 0 end
        if d > 100 then d = 100 end
        
        local on_ms = (window_ms * d) / 100
        if counter < on_ms then
            gpio.set(11, 1)
        else
            gpio.set(11, 0)
        end
        
        sys.wait(slice_ms)
        counter = counter + slice_ms
        if counter >= window_ms then
            counter = 0
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
