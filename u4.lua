local u4 = {}
function u4.init1()
    sys.taskInit(function()
        uart_id = 4
    uart.on(uart_id, "recv", function(id, len)
        -- local s = ""
        -- repeat

        -- 如果是air302, len不可信, 传1024
        -- s = uart.read(id, 1024)
        s = uart.read(id, len)
        log.info("uart", "receive", id, #s, s:toHex())
        if #s > 0 then -- #s 是取字符串的长度
            -- 如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
            -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
            -- log.info("uart", "receive", id, #s, string.toHex(s))

            local idx, crc = pack.unpack(s:sub(-2, -1), "H")
            local tmp = s:sub(1, -3)
            if crc == crypto.crc16("MODBUS", tmp) then

                local _, co = 0,0
                 _, co = pack.unpack(tmp, ">H", 4)
                -- log.info(co, relay1on)
                log.info("uart", "receive", id, #s, s:toHex())
                -- if co >= relay1on then
                --     if _G.onoff == 0 then
                --         if _G.tstart >= 300 then
                --             -- log.info("1", relay1delay)
                --             _G.onoff = 1
                --             kcon(10)
                --             sys.timerStart(kcoff, relay1delay * 60000) --按分钟延时关闭
                --         end
                --     end
                -- elseif co < relay1on - relay1delay then
                --     -- gpio.set(25, 0)
                --     -- gpio.set(24, 0)
                --     onoff = 0
                -- else
                --     -- gpio.set(25, 0)
                --     -- gpio.set(24, 0)
                --     onoff = 0
                -- end

                -- log.info("uart", "receive", id, #s, s:toHex())
                -- gpio.set(10, 0)
                -- log.info(start, datalen)

                -- for i = 1, datalen*2 do print(start+i) end
                -- local dd1 = rsptb[0x03][0]
                -- local dd2 = rsptb[0x03][1]
                -- local dd3 = rsptb[0x03][2]
                -- local dd4 = rsptb[0x03][3]
                -- local dd5 = rsptb[0x03][4]
                -- local dd6 = rsptb[0x03][5]

                -- log.info(dd1)
                -- log.info(dd2)
                -- log.info(dd3)
                -- log.info(dd4)
                -- log.info(dd5)
                -- log.info(dd6,"\n写入之前")

                -- nextpos, dev, func, count, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12 =
                --     pack.unpack(s, ">b15")
                -- log.info(v1)
                -- for i = 1, 2 do
                --     local dataadd = math.floor(0 + i)
                --     -- log.info(dataadd)
                --     -- local _,stmp = pack.unpack(s:sub(4, -1), "H")
                --     -- log.info("接收",s:toHex())
                --     local _, datatmp =
                --         pack.unpack(s:sub(3 + i, 4 + i), ">b1")

                --     number1 = 0 * 2 + i - 1

                --     -- log.info(number1)
                --     -- log.info(_G["v" .. i])
                --     -- rsptb[0x03][math.floor(number1)] = _G["v" .. i]
                --     if datatmp then
                --         -- log.info(number1)
                --         -- log.info(datatmp)
                --         -- rsptb[func][math.floor(number1)] = datatmp
                --     end
                -- end
                nextpos, dev, func, count, v1, v2, v3, v4, v5 =
                    pack.unpack(s, ">b3H5")

                if dev == 0xFF then
                    -- log.info(v1, v2, v3, v4, v5)
                    -- local wd = pack.pack(">f", v1 / 100)
                    -- local sd = pack.pack(">f", v2 / 100)
                    -- local yl = pack.pack(">f", v3 / 100)
                    -- local fs = pack.pack(">f", v4 / 100)
                    -- local fx = pack.pack(">f", v5 / 10)
                    -- -- log.info(fs:toHex())
                    -- for i = 1, #fs do
                    --     rsptb[0x03][math.floor(i - 1)] = fs:byte(i)
                    --     rsptb[0x03][math.floor(i + 3)] = fx:byte(i)
                    --     rsptb[0x03][math.floor(i + 15)] = wd:byte(i)
                    --     rsptb[0x03][math.floor(i + 19)] = sd:byte(i)
                    --     rsptb[0x03][math.floor(i + 23)] = yl:byte(i)
                    --     -- print(wd333:byte(i))
                    -- end
                end
                -- local dd1 = rsptb[0x03][0]
                -- local dd2 = rsptb[0x03][1]
                -- local dd3 = rsptb[0x03][2]
                -- local dd4 = rsptb[0x03][3]
                -- local dd5 = rsptb[0x03][4]
                -- local dd6 = rsptb[0x03][5]

                -- log.info(dd1)
                -- log.info(dd2)
                -- log.info(dd3)
                -- log.info(dd4)
                -- log.info(dd5)
                -- log.info(dd6,"\n上传之后")

                if count == 0x06 then
                    -- log.info("nextpos ,dev, func ", nextpos,
                    -- string.format("%02X,%02X,%02X,%02X,%02X", dev, func, count, v1, v2))
                    -- log.info(#data - 5)
                    for i = 1, #s - 5 do
                        rsptb[0x03][i] = _G["v" .. i]
                    end

                    -- rsptb[0x03][1] = v1
                    -- rsptb[0x03][2] = v2
                    -- rsptb[0x03][3] = v3
                    -- rsptb[0x03][4] = v4
                    -- rsptb[0x03][5] = v5
                    -- rsptb[0x03][6] = v6
                    -- log.info(rsptb[0x03][1], rsptb[0x03][2])
                end
                -- gpio.set(10, 1)
            end
        end
        -- until s == ""
        --     local data = uart.read(1, -3)
        --     local _,addr,Instructions,reg,v1,v2,v3 = pack.unpack(data,">b3H3")
        --     -- log.info(string.toHex(data))
        --     if reg == 0x06 then
        --         log.info(string.toHex(data))
        --         -- log.info("温度：", v1/100 .."℃" )
        --         -- log.info("湿度：", v2/100 .."℃" )
        --         -- log.info("压力：", v3/100 .."℃" )
        --         -- lvgl.label_set_text(label, v1/100)
        --     end
    end)

    local function modbus_send3(uart_id, slaveaddr, Instructions, reg, value)
        local data = (string.format("%02x", slaveaddr) ..
            string.format("%02x", Instructions) ..
            string.format("%04x", reg) ..
            string.format("%04x", value)):fromHex()
        local modbus_crc_data =
            pack.pack('<h', crypto.crc16("MODBUS", data))
        local data_tx = data .. modbus_crc_data
        -- log.info("S2", data_tx:toHex())
        uart.write(uart_id, data_tx)
    end

    while 1 do
        modbus_send3(uart_id, 0xFF, 0x03, 0x09, 0x05)
        -- modbus_send3(2, 0xFA, 0x03, 0x09, 0x05)
        -- log.info("发送串口3")
        -- _G.tstart = tstart + 1
        sys.wait(1000)
    end
    end)
end

return u4
