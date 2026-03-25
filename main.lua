PROJECT = "PLC-7k-2485-232-4i"
VERSION = "1.0.3"
sys = require("sys")
if wdt then
wdt.init(9000)--初始化watchdog设置为9s
sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end
local function bandchange(band)
local band_table = {[0]=2400, [1]=4800, [2]=9600, [3]=19200, [4]=38400, [5]=57600, [6]=115200, [7]=230400, [8]=460800, [9]=921600, [10]=2000000}
local result = band_table[band] or 9600
return result
end
if _G.rsptb == nil then
_G.rsptb = {}
rsptb[0x01] = {}
rsptb[0x02] = {}
for i = 0, 7 do rsptb[0x01][i] = 0x00 end
for i = 0, 7 do rsptb[0x02][i] = 0x00 end
rsptb[0x03] = {}
for i = 0, 199 do rsptb[0x03][i] = 0x00 end
rsptb[0x04] = {}
for i = 0, 199 do rsptb[0x04][i] = 0x00 end
end
fskv.init()
log.style(1)
if not fskv.get("u0") then
fskv.set("u0", {1, 2, 8, 0, 1})  -- {add, band, databit, crc, stop}
else
end
local u0_config = fskv.get("u0") or {1, 2, 8, 0, 1}  -- 获取完整配置，有默认值
_G.addr0 = u0_config[1] or 1  -- 设备地址 (add)
_G.band0 = bandchange(u0_config[2] or 9600)  -- 波特率 (band)
_G.databit0 = u0_config[3] or 8  -- 数据位 (databit)
_G.crc0 = u0_config[4] or 0  -- CRC校验 (crc)
_G.stop0 = u0_config[5] or 1  -- 停止位 (stop)
local function swap_bytes_zbuff(data_string, pattern)
local buff = zbuff.create(4)
buff:copy(0, data_string, 0, 4)
local temp = zbuff.create(4)
if pattern == "ABCD" then
return data_string
elseif pattern == "DCBA" then
temp:copy(0, buff, 3, 1)
temp:copy(1, buff, 2, 1)
temp:copy(2, buff, 1, 1)
temp:copy(3, buff, 0, 1)
elseif pattern == "BADC" then
temp:copy(0, buff, 1, 1)
temp:copy(1, buff, 0, 1)
temp:copy(2, buff, 3, 1)
temp:copy(3, buff, 2, 1)
elseif pattern == "CDAB" then
temp:copy(0, buff, 2, 1)
temp:copy(1, buff, 3, 1)
temp:copy(2, buff, 0, 1)
temp:copy(3, buff, 1, 1)
end
return temp:toStr(0, 4)
end
function _G.calc_crc16(data)
local crc = 0xFFFF
for i = 1, #data do
crc = bit.bxor(crc, string.byte(data, i))
for j = 1, 8 do
if bit.band(crc, 1) == 1 then
crc = bit.bxor(bit.rshift(crc, 1), 0xA001)
else
crc = bit.rshift(crc, 1)
end
end
end
return bit.band(crc, 0xFFFF)
end
function pack_modbus_data(value, data_type)
local format
local buff = zbuff.create(4)
if data_type == "char" then
format = ">c"
local value1 = math.floor(value + 0.5)
return pack.pack(format, value1)
elseif data_type == "uchar" then
format = ">b"
local value1 = math.floor(value + 0.5)
if value1 < 0 then value1 = 0 end
return pack.pack(format, value1)
elseif data_type == "short" then
format = ">h"
local value1 = math.floor(value + 0.5)
return pack.pack(format, value1)
elseif data_type == "ushort" then
format = ">H"
local value1 = math.floor(value + 0.5)
if value1 < 0 then value1 = 0 end
return pack.pack(format, value1)
elseif data_type == "int" then
format = ">i"
local value1 = math.floor(value + 0.5)
local packed = pack.pack(format, value1)
return packed
elseif data_type == "uint" then
format = ">I"
local value1 = math.floor(value + 0.5)
if value1 < 0 then value1 = 0 end
return pack.pack(format, value1)
elseif data_type == "ABCD" then
buff:pack(">f", value)
return buff:toStr(0, 4)
elseif data_type == "DCBA" then
buff:pack(">f", value)
return buff:toStr(0, 4)
elseif data_type == "BADC" then
buff:pack(">f", value)
return swap_bytes_zbuff(buff:toStr(0, 4), "BADC")
elseif data_type == "CDAB" then
buff:pack(">f", value)
return swap_bytes_zbuff(buff:toStr(0, 4), "CDAB")
elseif data_type == "digital" then
local packed = 0
for i, bit in ipairs(value) do
packed = packed | (bit << (i-1))
end
return string.char(packed)
else
buff:pack(">f", value)
return buff:toStr(0, 4)
end
end
function store_to_rsptb(value, data_type,  start_byte)
if start_byte < 1 then start_byte = 1 end
local packed = pack_modbus_data(value, data_type)
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
gpio.setup(30,1, gpio.PULLUP) --PT1
gpio.setup(29,1, gpio.PULLUP) --PT2
gpio.setup(28,1, gpio.PULLUP) --PT3
local function get_baud(code)
local bauds = {[0]=2400, [1]=4800, [2]=9600, [3]=19200, [4]=38400, [5]=57600, [6]=115200}
return bauds[code] or 9600
end
function _G.apply_uart_config()
local def = {baud_code=2, parity=0, stop=1} -- 9600, NONE, 1
local u1_cfg = fskv.get("cfg_u1") or def
local u2_cfg = fskv.get("cfg_u2") or def
local u4_cfg = fskv.get("cfg_u4") or def
local function get_parity(code)
if code == 1 then return uart.ODD end
if code == 2 then return uart.EVEN end
return uart.NONE
end
uart.setup(1, get_baud(u1_cfg.baud_code), 8, u1_cfg.stop, get_parity(u1_cfg.parity), uart.LSB, 1024, nil, 0, 2000)
uart.setup(2, get_baud(u2_cfg.baud_code), 8, u2_cfg.stop, get_parity(u2_cfg.parity), uart.LSB, 1024, 14, 0, 2000)
uart.setup(4, get_baud(u4_cfg.baud_code), 8, u4_cfg.stop, get_parity(u4_cfg.parity), uart.LSB, 1024, 43, 0, 2000)
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
u1.init1()
u2.init1()
u4.init1()
gpio.setup(8,0) --开关4 --采样泵
gpio.setup(9,0) --开关5 --标定阀
gpio.setup(10,0) --开关6 --原位标定阀
gpio.setup(11,0) --开关7 --预留PWM11
gpio.setup(5,0) --继电器 --报警输出
local last_sys_state = 0 -- 0:空闲/其他, 1:标定, 2:原位标定
local function recompute_buttons()
local s = (gpio.get(2) == 0)
local c = (gpio.get(3) == 0)
local m = (gpio.get(6) == 0)
local b = (gpio.get(7) == 0)
local pump, cal, insitu = 0, 0, 0
local current_sys_state = 0
if c and b then
pump, insitu, cal = 1, 1, 0
current_sys_state = 2 -- 原位标定状态
elseif c and (not b) then
pump, insitu, cal = 0, 0, 1
current_sys_state = 1 -- 标定状态
elseif s then
pump, insitu, cal = 1, 0, 0
current_sys_state = 0
else
pump, insitu, cal = 0, 0, 0
current_sys_state = 0
end
gpio.set(8, pump)
gpio.set(9, cal)
gpio.set(10, insitu)
if current_sys_state ~= last_sys_state then
if current_sys_state == 1 or current_sys_state == 2 then
if u4 and u4.write_reg then
local state_name = current_sys_state == 1 and "标定" or "原位标定"
u4.write_reg(0x64, 0x0084, 0x0001, 3, 1000, function(success, data)
if success then
else
log.error("系统状态", string.format("%s 0x06 指令下发失败/超时", state_name))
end
end)
end
end
last_sys_state = current_sys_state
end
if not rsptb[0x01] then rsptb[0x01] = {} end
if not rsptb[0x02] then rsptb[0x02] = {} end
local in_byte = (s and 1 or 0) | ((c and 1 or 0) << 1) | ((m and 1 or 0) << 2) | ((b and 1 or 0) << 3)
local alarm_on = (gpio.get(5) == 1) and 1 or 0
local out_byte = (pump & 1) | ((cal & 1) << 1) | ((insitu & 1) << 2) | (alarm_on << 3)
rsptb[0x02][0] = in_byte
rsptb[0x01][0] = out_byte
pcall(store_to_rsptb, m and 1 or 0, "ushort", 101)
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
local pwm_freq = 5
pwm.open(32, pwm_freq, 0)
pwm.open(33, pwm_freq, 0)
pwm.open(34, pwm_freq, 0)
local temp_manager = require("temp_manager")
local PT = require("pt100_control")
temp_manager.start({ id = 1, cpol = 1, cpha = 1, databits = 8, clock = 1 * 1000 * 1000 }, { _G.p1, _G.p2, _G.p3 }, 10)
sys.taskInit(function()
while 1 do
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
sys.run()