-- rtc_sync.lua
-- 实时时钟同步模块：从 HT1382 读取时间并同步到系统 RTC

local rtc_sync = {}

local sys = require("sys")
local ht1382 = require "ht1382"

-- 将 HT1382 读出的 tm 表转换为 UTC 时间表（用于 rtc.set）
local function tm_to_utc_table(tm, tz_offset_hours)
    tz_offset_hours = tz_offset_hours or 0
    -- os.time 按本地时区解析，这里先构造本地时间戳，再减去时区偏移，最后转 UTC 表
    local ts_local = os.time({ year = tm.tm_year, month = (tm.tm_mon or 0) + 1, day = tm.tm_mday, hour = tm.tm_hour, min = tm.tm_min, sec = tm.tm_sec })
    local ts_utc = ts_local - (tz_offset_hours * 3600)
    local ut = os.date("!*t", ts_utc)
    return { year = ut.year, mon = ut.month, day = ut.day, hour = ut.hour, min = ut.min, sec = ut.sec }
end

-- 将 UTC 时间表转换为本地时间表（用于写入 HT1382）
local function utc_to_local_table(utc_tbl, tz_offset_hours)
    tz_offset_hours = tz_offset_hours or 0
    local ts_utc = os.time(utc_tbl)
    local ts_local = ts_utc + (tz_offset_hours * 3600)
    local local_tbl = os.date("*t", ts_local)
    return { year = local_tbl.year, mon = local_tbl.month, day = local_tbl.day, hour = local_tbl.hour, min = local_tbl.min, sec = local_tbl.sec }
end

-- 开始同步任务
-- i2c_id: I2C 总线号（默认 0）
-- interval_ms: 同步间隔（默认 60000ms）
-- tz_offset_hours: 芯片内时间相对 UTC 的偏移（例如芯片里是北京时间则传 8；若芯片已存 UTC 则传 0）
function rtc_sync.start(i2c_id, interval_ms, tz_offset_hours)
    i2c_id = i2c_id or 0
    interval_ms = interval_ms or 60000
    tz_offset_hours = tz_offset_hours or 0

    sys.taskInit(function()
        -- 初始化 I2C 和 RTC 芯片
        i2c.setup(i2c_id, i2c.FAST)
        ht1382.init(i2c_id)
        
        log.info("rtc_sync", "启动时钟同步，I2C总线:", i2c_id, "同步间隔:", interval_ms, "时区偏移:", tz_offset_hours)

        -- 首次同步
        local ok, tm = pcall(ht1382.read_time)
        if ok and tm and tm.tm_year then
            local utc_tbl = tm_to_utc_table(tm, tz_offset_hours)
            rtc.set(utc_tbl)
            log.info("rtc_sync", "首次同步成功:", json.encode(tm), "-> UTC:", json.encode(utc_tbl))
        else
            log.error("rtc_sync", "首次同步失败:", tm)
        end

        -- 周期同步（智能同步，避免与网络时间冲突）
        while true do
            sys.wait(interval_ms)
            
            -- 检查网络状态，如果网络已连接且时间已同步，则跳过 RTC 同步
            local sys_time = os.date("*t")
            if sys_time.year > 2020 and sys_time.year < 2030 then
                -- 系统时间看起来是有效的，可能是网络同步的结果
                -- log.info("rtc_sync", "检测到系统时间已同步，跳过 RTC 同步:", 
                --     string.format("%04d-%02d-%02d %02d:%02d:%02d", 
                --     sys_time.year, sys_time.month, sys_time.day, sys_time.hour, sys_time.min, sys_time.sec))
                goto continue
            end
            
            local ok2, tm2 = pcall(ht1382.read_time)
            if ok2 and tm2 and tm2.tm_year then
                local utc_tbl2 = tm_to_utc_table(tm2, tz_offset_hours)
                rtc.set(utc_tbl2)
                log.info("rtc_sync", "周期同步成功:", json.encode(tm2), "-> UTC:", json.encode(utc_tbl2))
            else
                log.error("rtc_sync", "周期同步失败:", tm2, "保持系统时间不变")
            end
            
            ::continue::
        end
    end)
end

-- 配置/设置时钟（优化版本）
-- t: 时间表，支持多种格式：
--     {year, mon(1-12), day, hour, min, sec} 或 
--     {tm_year, tm_mon(0-11), tm_mday, tm_hour, tm_min, tm_sec}
--     或者时间字符串 "20250820095111" (本地时间)
-- is_utc: 传入的时间是否为 UTC（默认 true）
-- tz_offset_hours: 若 is_utc 为 false，此参数表示本地相对 UTC 的偏移小时数（例如本地为东八区传 8）
function rtc_sync.set_clock(t, is_utc, tz_offset_hours)
    is_utc = (is_utc == nil) and true or is_utc
    tz_offset_hours = tz_offset_hours or 0

    local year, month1_12, day, hour, min, sec

    -- 检查是否为时间字符串格式 "20250820095111"
    if type(t) == "string" and #t == 14 then
        -- 解析时间字符串：20250820095111 -> 2025-08-20 09:51:11
        year = tonumber(t:sub(1, 4))
        month1_12 = tonumber(t:sub(5, 6))
        day = tonumber(t:sub(7, 8))
        hour = tonumber(t:sub(9, 10))
        min = tonumber(t:sub(11, 12))
        sec = tonumber(t:sub(13, 14))
        
        log.info("rtc_sync", "解析时间字符串:", t, "->", string.format("%04d-%02d-%02d %02d:%02d:%02d", year, month1_12, day, hour, min, sec))
        
        -- 时间字符串默认为本地时间
        is_utc = false
        tz_offset_hours = tz_offset_hours or 8  -- 默认东八区
    else
        -- 统一成 {year, month, day, hour, min, sec}
        year = t.year or t.tm_year
        month1_12 = t.month or t.mon or ((t.tm_mon or 0) + 1)
        day = t.day or t.tm_mday
        hour = t.hour or t.tm_hour
        min = t.min or t.tm_min
        sec = t.sec or t.tm_sec
    end

    log.info("rtc_sync", "设置时钟，输入时间:", string.format("%04d-%02d-%02d %02d:%02d:%02d", 
        year, month1_12, day, hour, min, sec), "UTC:", is_utc, "时区偏移:", tz_offset_hours)

    -- 转成 UTC 时间戳
    local ts = os.time({ year = year, month = month1_12, day = day, hour = hour, min = min, sec = sec })
    if not is_utc then
        ts = ts - (tz_offset_hours * 3600)
        log.info("rtc_sync", "本地时间转换为 UTC，减去", tz_offset_hours, "小时")
    end
    local ut = os.date("!*t", ts)

    -- 写入 HT1382：芯片存储 UTC 时间
    local tm_set = {
        tm_year = ut.year,
        tm_mon = ut.month - 1,
        tm_mday = ut.day,
        tm_hour = ut.hour,
        tm_min = ut.min,
        tm_sec = ut.sec
    }
    
    log.info("rtc_sync", "写入 HT1382 的 UTC 时间:", string.format("%04d-%02d-%02d %02d:%02d:%02d", 
        tm_set.tm_year, tm_set.tm_mon + 1, tm_set.tm_mday, tm_set.tm_hour, tm_set.tm_min, tm_set.tm_sec))
    
    ht1382.set_time(tm_set)

    -- 同步到系统 RTC（UTC）
    rtc.set({ year = ut.year, mon = ut.month, day = ut.day, hour = ut.hour, min = ut.min, sec = ut.sec })
    
    log.info("rtc_sync", "系统 RTC 设置为 UTC:", string.format("%04d-%02d-%02d %02d:%02d:%02d", 
        ut.year, ut.month, ut.day, ut.hour, ut.min, ut.sec))
end

-- 快速设置本地时间字符串（推荐使用）
-- time_str: 时间字符串，格式 "20250820095111" (本地时间)
-- tz_offset: 时区偏移小时数（默认 8，适用于北京时间）
function rtc_sync.set_local_time_str(time_str, tz_offset)
    tz_offset = tz_offset or 8
    rtc_sync.set_clock(time_str, false, tz_offset)
end

-- 快速设置 UTC 时间（简化接口）
-- utc_time: {year, month, day, hour, min, sec} UTC 时间
function rtc_sync.set_utc_time(utc_time)
    rtc_sync.set_clock(utc_time, true, 0)
end

-- 快速设置时间（不进行时区转换，直接使用输入时间）
-- time: {year, month, day, hour, min, sec} 时间
function rtc_sync.set_time_direct(time)
    log.info("rtc_sync", "直接设置时间，不进行时区转换:", string.format("%04d-%02d-%02d %02d:%02d:%02d", 
        time.year, time.month, time.day, time.hour, time.min, time.sec))
    
    -- 直接写入 HT1382（假设芯片存储的就是这个时间）
    local tm_set = {
        tm_year = time.year,
        tm_mon = time.month - 1,
        tm_mday = time.day,
        tm_hour = time.hour,
        tm_min = time.min,
        tm_sec = time.sec
    }
    
    ht1382.set_time(tm_set)
    
    -- 直接设置系统 RTC（不进行时区转换）
    rtc.set({ year = time.year, mon = time.month, day = time.day, hour = time.hour, min = time.min, sec = time.sec })
    
    log.info("rtc_sync", "时间设置完成，系统RTC:", string.format("%04d-%02d-%02d %02d:%02d:%02d", 
        time.year, time.month, time.day, time.hour, time.min, time.sec))
end

return rtc_sync


