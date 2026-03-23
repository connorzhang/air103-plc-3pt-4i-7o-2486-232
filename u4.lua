local u4 = {}
function u4.init1()
    sys.taskInit(function()
        local uart_id = 4
        uart.on(uart_id, "recv", function(id, len)
            local s = uart.read(id, len)
            log.info("uart4", "receive", id, #s, s:toHex())
            if #s > 0 then
                log.info("uart4", "receive", id, #s, string.toHex(s))
                local idx, crc = pack.unpack(s:sub(-2, -1), "H")
                local tmp = s:sub(1, -3)
                if crc == crypto.crc16("MODBUS", tmp) then
                    local _, co = pack.unpack(tmp, ">H", 4)
                    log.info("uart4", "receive", id, #s, s:toHex())
                    
                    local nextpos, dev, func, count, v1, v2, v3, v4, v5 = pack.unpack(s, ">b3H5")

                    if count == 0x06 then
                        for i = 1, #s - 5 do
                            if _G["v" .. i] then
                                rsptb[0x03][i] = _G["v" .. i]
                            end
                        end
                    end
                end
            end
        end)

        local function modbus_send3(uart_id, slaveaddr, Instructions, reg, value)
            local data = (string.format("%02x", slaveaddr) ..
                string.format("%02x", Instructions) ..
                string.format("%04x", reg) ..
                string.format("%04x", value)):fromHex()
            local modbus_crc_data = pack.pack('<h', crypto.crc16("MODBUS", data))
            local data_tx = data .. modbus_crc_data
            uart.write(uart_id, data_tx)
        end

        while 1 do
            modbus_send3(uart_id, 0xFF, 0x03, 0x09, 0x05)
            sys.wait(1000)
        end
    end)
end

return u4
