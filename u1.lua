local u1 = {}
function u1.init1()
    local THISDEV = 20

    -- 保持系统处于唤醒状态，此处只是为了测试需要，所以此模块没有地方调用pm.sleep("testUart")休眠，不会进入低功耗休眠状态
    -- 在开发“要求功耗低”的项目时，一定要想办法保证pm.wake("modbusrtu")后，在不需要串口时调用pm.sleep("testUart")
    -- pm.wake("modbusrtuslav")

    local uart_id = 1
    local uart_baud = band1
    --[[
--   起始        地址    功能代码    数据       CRC校验    结束
-- 3.5 字符     8 位      8 位      N x 8 位   16 位      3.5 字符
--- 发送modbus数据函数
@function   modbus_resp
@param      slaveaddr : 从站地址
            Instructions:功能码
            hexdat 回复的数据 HEX STRING
@return     无
@usage modbus_resp("0x01","0x01","0x0101","0x04")
]]
    local function modbus_resp(slaveaddr, Instructions, hexdat)
        local data = (string.format("%02x", slaveaddr) ..
            string.format("%02x", Instructions) .. hexdat):fromHex()
        local modbus_crc_data = pack.pack('<h', crypto.crc16("MODBUS", data))
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

    -- 读取SHT40的温湿度值
    local function read_sht40(id)
        i2c.setup(id)
        sys.wait(50)
        i2c.send(id, 0x44, 0xFD) -- 发送测量指令，从时钟拉高到数据输出需最少15ms
        sys.wait(50)             -- 18ms或20ms，自行参考官方文档和数据手册
        -- 高字节后移8位与低字节合并，得到温度值
        local c = i2c.recv(1, 0x44, 6)
        _G.t11 = (c:byte(1) * 256 + c:byte(2)) * 175 / 65535 - 45
        _G.h11 = (c:byte(4) * 256 + c:byte(5)) * 100 / 65535
        t111 = string.format("%.0f", t11 * 100)
        h111 = string.format("%.0f", h11 * 100)
        local data_t_hex = pack.pack(">H", t111)
        local data_h_hex = pack.pack(">H", h111)

        --  log.info(#data_t_hex)
        for i = 1, #data_t_hex do
            rsptb[0x03][i] =
                (string.format("%02x ", data_t_hex:byte(i))):fromHex()
            rsptb[0x04][i] =
                (string.format("%02x ", data_t_hex:byte(i))):fromHex()

            rsptb[0x03][i + 2] =
                (string.format("%02x ", data_h_hex:byte(i))):fromHex()
            rsptb[0x04][i + 2] =
                (string.format("%02x ", data_h_hex:byte(i))):fromHex()

            --     log.info( (rsptb[0x04][i]):toHex())
        end
        -- 下一次读取数据前至少要有2ms的延时
        sys.wait(20)
        i2c.close(id)
        return t111, h111
    end

    -- 配置并且打开串口
    -- uart.setup(uart_id, uart_baud, 8, uart.PAR_NONE, uart.STOP_1)
    -- 注册串口的数据发送通知函数
    uart.on(uart_id, "recv", function(id, len)
        local cacheData = uart.read(id, len)
        if cacheData:len() > 0 then
            local a = string.toHex(cacheData)
            -- aa=cacheData:sub(1,-3)
            log.info("modbus接收数据1:", cacheData:toHex())
            local nextpos, dev, func = pack.unpack(cacheData, "bb", 1)
            -- log.info("nextpos ,dev, func ", nextpos, string.format("%02X,%02X", dev, func))
            -- 01 06 0001 0002 59CB
            local idx, crc = pack.unpack(cacheData:sub(-2, -1), "H")
            local tmp = cacheData:sub(1, -3)
            if crc == crypto.crc16("MODBUS", tmp) then
                -- gpio.set(8, 0)

                local nextpos, dev, func, v1, v2, v3, v4, v5, v6, v7, v8, v9,
                v10, v11, v12 = pack.unpack(cacheData, ">b15")

                -- log.info(start)

                if func == 0x01 or func == 0x02 or func == 0x03 or func == 0x04 or
                    func == 0x05 or func == 0x06 then
                    if #cacheData >= 8 then
                        local strcrc = pack.pack('<h', crypto.crc16("MODBUS",
                            cacheData:sub(
                                1, 6)))
                        if strcrc == cacheData:sub(7, 8) then
                            local _, reg, val =
                                pack.unpack(cacheData, ">H>H", nextpos)

                            -- log.info("a-func,crc is correct!", func, string.format("reg=0x%04X, val=0x%04X", start, datalen))
                            -- 校验正确后，根据不同的功能码做回复(DEMO 忽略起始地址)
                            local _, bytstart = pack.unpack(cacheData, ">H", 3) -- 启始地址
                            local _, bytlen = pack.unpack(cacheData, ">H", 5)   -- 个数
                            
                            if func == 0x01 then
                                if THISDEV == dev or dev == 0xFA then
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
                                        out_bytes[#out_bytes + 1] = string.format("%02x", val)
                                    end
                                    local payload = table.concat(out_bytes, "")
                                    modbus_resp(THISDEV, func, string.format("%02x%s", nbytes, payload))
                                end
                            elseif func == 0x02 then
                                if THISDEV == dev or dev == 0xFA then
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
                                        out_bytes[#out_bytes + 1] = string.format("%02x", val)
                                    end
                                    local payload = table.concat(out_bytes, "")
                                    modbus_resp(THISDEV, func, string.format("%02x%s", nbytes, payload))
                                end
                            elseif func == 0x03 or func == 0x04 then
                                -- _G.t1,_G.h1 = read_sht40(0)
                                -- log.info(t1,h1)
                                -- if i2c.exist(0) then
                                -- log.info("存在 i2c0")
                                -- else
                                -- log.info("不存在 i2c0")
                                -- end
                                if THISDEV == dev or dev == 0xFA then
                                    local bytlens = bytlen * 2
                                    local bytstarts = bytstart * 2
                                    if (bytlens + bytstart) <= #rsptb[func] then
                                        local strhex = ""
                                        for i = bytstarts, bytlens + bytstarts - 1 do
                                            local tmpdata = 0X00
                                            -- log.info("数量1",i)
                                            if rsptb[func][i] then
                                                -- log.info("数量2",i)
                                                tmpdata =
                                                    string.format("%02x",
                                                        rsptb[func][i])
                                            end
                                            strhex = strhex .. tmpdata
                                        end
                                        if strhex then
                                            modbus_resp(THISDEV, func, string.format(
                                                "%02x%s", #strhex / 2,
                                                strhex))
                                        end
                                    else
                                        modbus_resp(THISDEV, func + 0x80,
                                            string.format("%02x", 0x02))
                                    end
                                else

                                end
                            elseif func == 0x05 then
                                -- Write Single Coil
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
                                modbus_resp(THISDEV, func, strhex)

                            elseif func == 0x06 then
                                local strhex = string.format("%04X%04X", bytstart, bytlen)
                                _G.handle_modbus_write(bytstart, bytlen, false)
                                modbus_resp(THISDEV, func, strhex)

                            else
                                log.info("unkonw func", func)
                                modbus_resp(THISDEV, func + 0x80,
                                    string.format("%02x", 0x01))
                            end
                        else
                            log.info("a-func #cacheData  crc, calcrc", func,
                                #cacheData, cacheData:sub(7, 8):toHex(),
                                strcrc:toHex())
                        end
                    end
                elseif func == 0x0F then
                    local dlen = cacheData:byte(nextpos + 4)
                    if #cacheData >= 7 + dlen + 2 then
                        local strcrc = pack.pack('<h', crypto.crc16("MODBUS",
                            cacheData:sub(1, 7 + dlen)))
                        if strcrc == cacheData:sub(7 + dlen + 1, 7 + dlen + 2) then
                            local _, reg, val = pack.unpack(cacheData, ">H>H", nextpos)
                            local tmpdat = cacheData:sub(8, dlen + 8 - 1)
                            log.info("b-func crc is correct!", func, dlen, "will save:", tmpdat:toHex())
                            local strhex = string.format("%04X%04X", reg, val)
                            modbus_resp(dev, func, strhex)
                        else
                            log.info("b-func,#cacheData  crc, calcrc", func,
                                #cacheData, cacheData:sub(7 + dlen + 1, 7 + dlen + 2):toHex(), strcrc:toHex())
                        end
                    end
                elseif func == 0x10 then
                    local dlen = cacheData:byte(nextpos + 4)
                    if #cacheData >= 7 then
                        local strcrc = pack.pack('<h', crypto.crc16("MODBUS", cacheData:sub(1, -3)))
                        if strcrc == cacheData:sub(-2, -1) then
                            local _, reg, val = pack.unpack(cacheData, ">H>H", nextpos)
                            local tmpdat = cacheData:sub(8, -3)
                            
                            -- Call our unified write handler
                            _G.handle_modbus_write(reg, tmpdat, true)
                            
                            local strhex = string.format("%04X%04X", reg, val)
                            modbus_resp(dev, func, strhex)
                        else
                            log.info("c-func,#cacheData  crc, calcrc", func,
                                #cacheData, cacheData:sub(7 + dlen + 1, 7 + dlen + 2):toHex(), strcrc:toHex())
                        end
                    end
                end
                -- gpio.set(8, 1)
            end
            -- MODBUS 暂时不考虑粘包的情况
            -- cacheData = ""--也没啥用
        end
    end)
end

return u1
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
-- sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
