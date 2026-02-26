
--[[
@module ht1382
@summary ht1382 实时时钟传感器
@version 1.0
@date    2022.03.16
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local ht1382 = require "ht1382"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    ht1382.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local time = ht1382.read_time()
        log.info("ht1382.read_time",time.tm_year,time.tm_mon,time.tm_mday,time.tm_hour,time.tm_min,time.tm_sec)
        sys.wait(5000)
        local set_time = {tm_year=2021,tm_mon=3,tm_mday=0,tm_wday=0,tm_hour=0,tm_min=0,tm_sec=0}
        ht1382.set_time(set_time)
        time = ht1382.read_time()
        log.info("ht1382_read_time",time.tm_year,time.tm_mon,time.tm_mday,time.tm_hour,time.tm_min,time.tm_sec)
        sys.wait(1000)
    end
end)
]]

local ht1382 = {}

local sys = require "sys"

local i2cid

local HT1382_ADDRESS            =   0x68 -- I2C地址与DS3231相同
local i2cslaveaddr              =   HT1382_ADDRESS --slave address

---HT1382所用地址
local REG_SEC                   =   0x00 -- BIT7为时钟停止位(1=停止)
local REG_MIN                   =   0x01
local REG_HOUR                  =   0x02 -- BIT7为12/24小时模式
local REG_DAY                   =   0x03
local REG_MON                   =   0x04
local REG_MON                   =   0x05
local REG_YEAR                  =   0x06
local REG_CONTROL               =   0x07 -- BIT7为写保护位(1=保护)

local function i2c_send(data)
    i2c.send(i2cid, i2cslaveaddr, data)
end

local function i2c_recv(data,num)
    i2c.send(i2cid, i2cslaveaddr, data)
    local revData = i2c.recv(i2cid, i2cslaveaddr, num)
    return revData
end

local function bcd_to_hex(data)
    local hex = bit.rshift(data,4)*10+bit.band(data,0x0f)
    return hex;
end

local function hex_to_bcd(data)
    local bcd = bit.lshift(math.floor(data/10),4)+data%10
    return bcd;
end

--[[
ht1382初始化
@api ht1382.init(i2c_id)
@number 所在的i2c总线id
@return bool   成功返回true
]]
function ht1382.init(i2c_id)
    i2cid = i2c_id
    i2c_send({REG_CONTROL, 0x80}) -- 关闭写保护
    log.info("ht1382 init_ok")
    return true
end

--[[
获取时间
@api ht1382.read_time()
@return table 时间表
]]
function ht1382.read_time()
    local time_data = {}
    -- local data = i2c_recv(REG_SEC, 7)
    i2c_send({REG_CONTROL, 0x80})
    -- i2c.send(0, 0x68, {0x07, 0x80})
    -- i2c.send(0, 0x68, {REG_CONTROL, 0x01})
    i2c.send(0, 0x68, {0x00, 0x01})
    -- i2c.send(0, 0x68, {0x09, 0x80})
    sys.wait(100)
    local data =  i2c.recv(0, 0x68, 16)
    log.info("data",json.encode(data))
    time_data.tm_sec  = bcd_to_hex(bit.band(data:byte(1), 0x7F)) -- 屏蔽时钟停止位
    time_data.tm_min  = bcd_to_hex(data:byte(2))
    time_data.tm_hour = bcd_to_hex(bit.band(data:byte(3), 0x3F)) -- 屏蔽12/24小时标志
    time_data.tm_mday = bcd_to_hex(data:byte(4))
    time_data.tm_mon  = bcd_to_hex(data:byte(5)) - 1
    time_data.tm_year = bcd_to_hex(data:byte(7)) + 2000
    return time_data
end

--[[
设置时间
@api ht1382.set_time(time)
@table time 时间表
]]
function ht1382.set_time(time)
    -- 先打开写保护
    i2c_send({REG_CONTROL, 0x00})
    
    local data = {
        0x00,
        hex_to_bcd(time.tm_sec),  -- 秒(自动清除停止位)
        hex_to_bcd(time.tm_min),  -- 分
        hex_to_bcd(time.tm_hour), -- 时(24小时制)
        hex_to_bcd(time.tm_mday), -- 日
        hex_to_bcd(time.tm_mon + 1), -- 月
        0x01,                     -- 星期(HT1382不单独存储)
        hex_to_bcd(time.tm_year - 2000) -- 年
    }
    i2c_send(data)
        -- 先关闭写保护
    i2c_send({REG_CONTROL, 0x80})
end

return ht1382
