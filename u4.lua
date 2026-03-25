local u4 = {}
local uart_id = 4
local is_polling_active = true
local poll_interval = 2000 -- 2秒轮询间隔
local poll_slave_addr = 0x64 -- 十进制 100
local poll_start_reg = 0x00D3 -- 十进制 211
local poll_reg_count = 0x06 -- 3个Float32，占6个寄存器
local data_store_start_reg = 12 -- 紧跟在温度(0~11)后面，起始字节索引为 25
local cmd_queue = {}
local is_processing = false
local function calc_crc(data)
return pack.pack('<h', crypto.crc16("MODBUS", data))
end
local function send_cmd_03(slaveaddr, reg, count)
local data = (string.format("%02x", slaveaddr) ..
string.format("%02x", 0x03) ..
string.format("%04x", reg) ..
string.format("%04x", count)):fromHex()
local data_tx = data .. calc_crc(data)
uart.write(uart_id, data_tx)
end
local function send_cmd_06(slaveaddr, reg, value)
local data = (string.format("%02x", slaveaddr) ..
string.format("%02x", 0x06) ..
string.format("%04x", reg) ..
string.format("%04x", value)):fromHex()
local data_tx = data .. calc_crc(data)
uart.write(uart_id, data_tx)
end
function u4.init1()
uart.on(uart_id, "recv", function(id, len)
local s = uart.read(id, len)
if #s > 0 then
if #s >= 5 then
local tmp = s:sub(1, -3)
local _, crc = pack.unpack(s:sub(-2, -1), "H")
if crc == crypto.crc16("MODBUS", tmp) then
local _, dev, func = pack.unpack(s, "bb", 1)
sys.publish("U4_MODBUS_RECV", dev, func, s)
else
log.error("u4", "CRC 校验失败", s:toHex())
end
end
end
end)
sys.taskInit(function()
while true do
if #cmd_queue > 0 then
is_processing = true
local task = table.remove(cmd_queue, 1)
local retry_count = 0
local success = false
while retry_count < task.max_retries and not success do
if task.func == 0x06 then
send_cmd_06(task.slaveaddr, task.reg, task.value)
end
local result, dev, func, s = sys.waitUntil("U4_MODBUS_RECV", task.timeout)
if result then
if dev == task.slaveaddr and func == task.func then
success = true
if task.callback then task.callback(true, s) end
else
log.warn("u4", "收到非预期的响应")
end
else
retry_count = retry_count + 1
log.warn("u4", string.format("响应超时，第 %d 次重试", retry_count))
end
end
if not success then
log.error("u4", string.format("功能码 %02X 执行失败，达到最大重试次数", task.func))
if task.callback then task.callback(false, nil) end
end
is_processing = false
sys.wait(100) -- 指令间隙
elseif is_polling_active then
is_processing = true
send_cmd_03(poll_slave_addr, poll_start_reg, poll_reg_count)
local result, dev, func, s = sys.waitUntil("U4_MODBUS_RECV", 1000)
if result and dev == poll_slave_addr and func == 0x03 then
local _, _, _, count = pack.unpack(s, "bbb")
if count == poll_reg_count * 2 and #s == (5 + count) then
local data_payload = s:sub(4, 3 + count)
_G.handle_modbus_write(data_store_start_reg, data_payload, true)
end
end
is_processing = false
sys.wait(poll_interval)
else
sys.wait(100)
end
end
end)
end
function u4.set_polling(active)
is_polling_active = active
end
function u4.write_reg(slaveaddr, reg, value, max_retries, timeout, callback)
table.insert(cmd_queue, {
func = 0x06,
slaveaddr = slaveaddr,
reg = reg,
value = value,
max_retries = max_retries or 3,
timeout = timeout or 1000,
callback = callback
})
end
return u4