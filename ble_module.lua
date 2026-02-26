local ble = {}
function ble.start()
    -- local nimble = require("nimble")
    -- nimble.setUUID("srv", string.fromHex("380D"))
    -- nimble.setUUID("write", string.fromHex("FF31"))
    -- nimble.setUUID("indicate", string.fromHex("FF32"))
    nimble.init("PLC-PT100")
    sys.taskInit(function()
        while 1 do
            local t1 = _G.pt1 or 999
            local t2 = _G.pt2 or 999
            local t3 = _G.pt3 or 999
            local d1 = _G.d1 or 0
            local d2 = _G.d2 or 0
            local d3 = _G.d3 or 0
            local tg1 = _G.tg1 or 0
            local tg2 = _G.tg2 or 0
            local tg3 = _G.tg3 or 0
            local payload = string.format("t=[%.2f,%.2f,%.2f],d=[%d,%d,%d],tg=[%.1f,%.1f,%.1f]", t1, t2, t3, d1, d2, d3, tg1, tg2, tg3)
            nimble.sendNotify(nil, string.fromHex("FF32"), payload)
            sys.wait(1000)
        end
    end)
end
return ble