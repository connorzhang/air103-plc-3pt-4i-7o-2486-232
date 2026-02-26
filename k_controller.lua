-- k_controller.lua - 最简单的ioqueue测试
local k_controller = {}

local sys = require("sys")

-- 继电器GPIO
local RELAY_PIN = 32  -- S0继电器
local HW_TIMER_ID = 1  -- 使用硬件定时器1

-- 连续延时的单位(us)，建议50ms，兼容性好
local IOQ_CONT_DELAY_US = 50000
-- ioqueue.setdelay的time_us最大限制
local IOQ_MAX_DELAY_US = 65535

-- 按秒追加连续延时：依赖于已调用 ioqueue.setdelay(HW_TIMER_ID, IOQ_CONT_DELAY_US, 0, true)
function k_controller.delay_s(seconds)
	seconds = tonumber(seconds) or 0
	if seconds <= 0 then return end
	
	-- 优化策略：短延时用循环，长延时用多次setdelay循环
	if seconds <= 1 then
		-- 短延时：用连续延时循环，精度高
		local repeats = math.floor((seconds * 1000000) / IOQ_CONT_DELAY_US + 0.5)
		for i = 1, repeats do
			ioqueue.delay(HW_TIMER_ID)
		end
	else
		-- 长延时：用多次setdelay循环，每次最大65ms
		local total_us = seconds * 1000000
		local cycles = math.ceil(total_us / IOQ_MAX_DELAY_US)
		local delay_per_cycle = math.floor(total_us / cycles)
		
		for i = 1, cycles do
			ioqueue.setdelay(HW_TIMER_ID, delay_per_cycle, 0, false)
		end
	end
end

-- 仅用ioqueue控制：输出高电平保持sec秒后输出低电平
function k_controller.test(sec)
	local seconds = tonumber(sec) or 2
	ioqueue.stop(HW_TIMER_ID)
	
	if seconds <= 1 then
		-- 短延时：用连续延时循环
		local repeats = math.floor((seconds * 1000000) / IOQ_CONT_DELAY_US + 0.5)
		local cmd_cnt = 4 + repeats
		ioqueue.init(HW_TIMER_ID, cmd_cnt, 1)
		ioqueue.setgpio(HW_TIMER_ID, RELAY_PIN, false, 0, 0)
		ioqueue.output(HW_TIMER_ID, RELAY_PIN, 1)
		ioqueue.setdelay(HW_TIMER_ID, IOQ_CONT_DELAY_US, 0, true)
		k_controller.delay_s(seconds)
		ioqueue.output(HW_TIMER_ID, RELAY_PIN, 0)
	else
		-- 长延时：用多次setdelay循环
		local total_us = seconds * 1000000
		local cycles = math.ceil(total_us / IOQ_MAX_DELAY_US)
		local delay_per_cycle = math.floor(total_us / cycles)
		local cmd_cnt = 3 + cycles  -- setgpio + output高 + N个setdelay + output低
		
		ioqueue.init(HW_TIMER_ID, cmd_cnt, 1)
		ioqueue.setgpio(HW_TIMER_ID, RELAY_PIN, false, 0, 0)
		ioqueue.output(HW_TIMER_ID, RELAY_PIN, 1)
		
		-- 添加多个setdelay命令
		for i = 1, cycles do
			ioqueue.setdelay(HW_TIMER_ID, delay_per_cycle, 0, false)
		end
		
		ioqueue.output(HW_TIMER_ID, RELAY_PIN, 0)
	end
	
	ioqueue.start(HW_TIMER_ID)
end

-- 启动
function k_controller.start()
	log.info("k_controller", "启动K控制器")
	-- 上升沿触发，默认开2秒
	sys.taskInit(function()
		local last_k1 = false
		while true do
			local cur = (_G.switch_states and _G.switch_states.k1) or false
			if cur and not last_k1 then
				k_controller.test(10)
			end
			last_k1 = cur
			sys.wait(50)
		end
	end)
end

return k_controller
