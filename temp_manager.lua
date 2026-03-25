local temp_manager = {}
local sys = require("sys")
local max31865 = require("max31865")
local cs_config = require("cs_config")
local sliding = { [1]={buf={},abn=0}, [2]={buf={},abn=0}, [3]={buf={},abn=0} }
local function update_avg(idx, t)
local st = sliding[idx]
if type(t) == "number" and t ~= 999 then
st.abn = 0
table.insert(st.buf, 1, t)
if #st.buf > 20 then table.remove(st.buf) end
else
st.abn = st.abn + 1
end
if st.abn > 3 then
return 999
end
if #st.buf == 0 then
return 999
end
local sum = 0
for _, v in ipairs(st.buf) do sum = sum + v end
return math.floor((sum / #st.buf))
end
function temp_manager.start(spi_cfg, pins, interval_ms)
pins = pins or cs_config.get_pins()
interval_ms = interval_ms or 100
_G.pt1, _G.pt2, _G.pt3 = _G.pt1, _G.pt2, _G.pt3
sys.taskInit(function()
local spi_id = (spi_cfg and spi_cfg.id) or 1
local cpol = (spi_cfg and spi_cfg.cpol) or 1
local cpha = (spi_cfg and spi_cfg.cpha) or 1
local databits = (spi_cfg and spi_cfg.databits) or 8
local clock = (spi_cfg and spi_cfg.clock) or (1 * 1000 * 1000)
local bitorder = (spi_cfg and spi_cfg.bitorder) or spi.MSB
local cs = (spi_cfg and spi_cfg.cs) or 1
local mode = (spi_cfg and spi_cfg.mode) or 0
local dev = spi.deviceSetup(spi_id, nil, cpol, cpha, databits, clock, bitorder, cs, mode)
max31865.init(dev, max31865.WIRE3, 255, pins)
max31865.diagnose_cs()
while true do
local t1 = max31865.temperature(pins[1])
_G.pt1 = (t1 ~= nil) and t1 or 999
local o1 = update_avg(1, _G.pt1)
pcall(store_to_rsptb, o1,  "ABCD", 1)
pcall(store_to_rsptb, pt1, "ABCD", 13)
local t2 = max31865.temperature(pins[2])
_G.pt2 = (t2 ~= nil) and t2 or 999
local o2 = update_avg(2, _G.pt2)
pcall(store_to_rsptb, o2,  "ABCD", 5)
pcall(store_to_rsptb, pt2,  "ABCD", 17)
local t3 = max31865.temperature(pins[3])
_G.pt3 = (t3 ~= nil) and t3 or 999
local o3 = update_avg(3, _G.pt3)
pcall(store_to_rsptb, o3,  "ABCD", 9)
pcall(store_to_rsptb, pt3,  "ABCD", 21)
sys.wait(interval_ms)
end
end)
end
return temp_manager