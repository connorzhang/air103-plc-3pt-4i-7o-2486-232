local u1 = {}

function u1.init1()
local uart_id = 1
local uart_baud = band1
local function modbus_resp(slaveaddr, Instructions, hexdat)
if #hexdat % 2 ~= 0 then
hexdat = "0" .. hexdat
end
local raw_hex_str = string.format("%02X", slaveaddr) .. string.format("%02X", Instructions) .. hexdat
local data = raw_hex_str:fromHex()
local crc_val = crypto.crc16("MODBUS", data)
local crc_low = bit.band(crc_val, 0xFF)
local crc_high = bit.band(bit.rshift(crc_val, 8), 0xFF)
local modbus_crc_data = string.char(crc_low, crc_high)
local data_tx = data .. modbus_crc_data
uart.write(uart_id, data_tx)
end
local function MSK_DIGI(pos)
local msk = 0
for i = 1, pos do
msk = bit.lshift(msk, 1)
msk = msk + 1
end
return msk
end
local function read_sht40(id)
i2c.setup(id)
sys.wait(50)
i2c.send(id, 0x44, 0xFD) -- 发送测量指令，从时钟拉高到数据输出需最少15ms
sys.wait(50)             -- 18ms或20ms，自行参考官方文档和数据手册
local c = i2c.recv(1, 0x44, 6)
_G.t11 = (c:byte(1) * 256 + c:byte(2)) * 175 / 65535 - 45
_G.h11 = (c:byte(4) * 256 + c:byte(5)) * 100 / 65535
t111 = string.format("%.0f", t11 * 100)
h111 = string.format("%.0f", h11 * 100)
local data_t_hex = pack.pack(">H", t111)
local data_h_hex = pack.pack(">H", h111)
for i = 1, #data_t_hex do
rsptb[0x03][i] =
(string.format("%02x ", data_t_hex:byte(i))):fromHex()
rsptb[0x04][i] =
(string.format("%02x ", data_t_hex:byte(i))):fromHex()
rsptb[0x03][i + 2] =
(string.format("%02x ", data_h_hex:byte(i))):fromHex()
rsptb[0x04][i + 2] =
(string.format("%02x ", data_h_hex:byte(i))):fromHex()
end
sys.wait(20)
i2c.close(id)
return t111, h111
end
uart.on(uart_id, "recv", function(id, len)
local cacheData = uart.read(id, len)
if cacheData:len() > 0 then
local tmp = cacheData:sub(1, -3)
local _, crc = pack.unpack(cacheData:sub(-2, -1), "H")
if crc == crypto.crc16("MODBUS", tmp) then
local _, dev, func = pack.unpack(cacheData, "bb", 1)
if func == 0x01 or func == 0x02 or func == 0x03 or func == 0x04 or func == 0x05 or func == 0x06 then
if #cacheData >= 8 then
local _, bytstart = pack.unpack(cacheData, ">H", 3)
local _, bytlen = pack.unpack(cacheData, ">H", 5)
if func == 0x01 then
if _G.u1_addr == dev or dev == 0xFA then
local nbytes = math.ceil(bytlen / 8)
local out_bytes = {}
for b = 0, nbytes - 1 do
local val = 0
for bitp = 0, 7 do
local k = bytstart + b * 8 + bitp
local byteIndex = math.floor(k / 8)
local bitPos = k % 8
local byteVal = (rsptb[func] and rsptb[func][byteIndex]) or 0
if bit.band(bit.rshift(byteVal, bitPos), 1) == 1 then
val = bit.bor(val, bit.lshift(1, bitp))
end
end
out_bytes[b + 1] = string.char(val)
end
local payload = table.concat(out_bytes)
local hex_payload = payload:toHex()
modbus_resp(_G.u1_addr, func, string.format("%02X%s", nbytes, hex_payload))
end
elseif func == 0x02 then
if _G.u1_addr == dev or dev == 0xFA then
local nbytes = math.ceil(bytlen / 8)
local out_bytes = {}
for b = 0, nbytes - 1 do
local val = 0
for bitp = 0, 7 do
local k = bytstart + b * 8 + bitp
local byteIndex = math.floor(k / 8)
local bitPos = k % 8
local byteVal = (rsptb[func] and rsptb[func][byteIndex]) or 0
if bit.band(bit.rshift(byteVal, bitPos), 1) == 1 then
val = bit.bor(val, bit.lshift(1, bitp))
end
end
out_bytes[b + 1] = string.char(val)
end
local payload = table.concat(out_bytes)
local hex_payload = payload:toHex()
modbus_resp(_G.u1_addr, func, string.format("%02X%s", nbytes, hex_payload))
end
elseif func == 0x03 or func == 0x04 then
if _G.u1_addr == dev or dev == 0xFA then
local bytlens = bytlen * 2
local bytstarts = bytstart * 2
if (bytstarts + bytlens) <= 400 then
local out_bytes = {}
for i = bytstarts, bytlens + bytstarts - 1 do
local tmpdata = 0x00
if rsptb[func] and rsptb[func][i] then
tmpdata = rsptb[func][i]
end
out_bytes[#out_bytes + 1] = string.format("%02X", tmpdata)
end
local strhex = table.concat(out_bytes)
modbus_resp(_G.u1_addr, func, string.format("%02X%s", bytlens, strhex))
else
modbus_resp(_G.u1_addr, func + 0x80, string.format("%02x", 0x02))
end
end
elseif func == 0x05 then
local coil_addr = bytstart
local coil_val = bytlen
local byteIndex = math.floor(coil_addr / 8)
local bitPos = coil_addr % 8
if not rsptb[0x01] then rsptb[0x01] = {} end
local currentByte = rsptb[0x01][byteIndex] or 0
if coil_val == 0xFF00 then
rsptb[0x01][byteIndex] = bit.bor(currentByte, bit.lshift(1, bitPos))
elseif coil_val == 0x0000 then
rsptb[0x01][byteIndex] = bit.band(currentByte, bit.bnot(bit.lshift(1, bitPos)))
end
local strhex = string.format("%04X%04X", bytstart, bytlen)
modbus_resp(_G.u1_addr, func, strhex)
elseif func == 0x06 then
local strhex = string.format("%04X%04X", bytstart, bytlen)
_G.handle_modbus_write(bytstart, bytlen, false)
modbus_resp(_G.u1_addr, func, strhex)
else
modbus_resp(_G.u1_addr, func + 0x80, string.format("%02x", 0x01))
end
end
elseif func == 0x0F then
local dlen = cacheData:byte(7)
if #cacheData >= 7 + dlen + 2 then
local strcrc = pack.pack('<h', crypto.crc16("MODBUS",
cacheData:sub(1, 7 + dlen)))
if strcrc == cacheData:sub(7 + dlen + 1, 7 + dlen + 2) then
local _, reg, val = pack.unpack(cacheData, ">H>H", 3)
local tmpdat = cacheData:sub(8, dlen + 8 - 1)
local strhex = string.format("%04X%04X", reg, val)
modbus_resp(dev, func, strhex)
end
end
elseif func == 0x10 then
local dlen = cacheData:byte(7)
if #cacheData >= 7 then
local strcrc = pack.pack('<h', crypto.crc16("MODBUS", cacheData:sub(1, -3)))
if strcrc == cacheData:sub(-2, -1) then
local _, reg, val = pack.unpack(cacheData, ">H>H", 3)
local tmpdat = cacheData:sub(8, -3)
log.info("u1.10", reg, val, dlen, tmpdat:toHex())
local status, err = pcall(_G.handle_modbus_write, reg, tmpdat, true)
if not status then log.error("u1.e", err) end
local strhex = ""
if reg ~= nil and val ~= nil then
strhex = string.format("%04X%04X", reg, val)
else
local _, raw_reg, raw_val = pack.unpack(cacheData, ">H>H", 3)
if raw_reg and raw_val then
strhex = string.format("%04X%04X", raw_reg, raw_val)
else
strhex = "00000000"
end
end
modbus_resp(_G.u1_addr, func, strhex)
end
end
end
end
end
end)
end
return u1