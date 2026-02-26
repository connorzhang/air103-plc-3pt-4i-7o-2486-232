# 采样系统PLC文件说明

## 📁 核心文件

### PLC控制器
- `plc_controller.lua` - 主PLC控制器，实现K1/K5/K9功能
- `plc_cfg_simple.lua` - 简化配置管理器（原plc_config_manager_simple.lua）
- `switch_monitor.lua` - 开关状态监控（K1-K11）

### 主程序
- `main.lua` - 主程序入口，启动所有模块

### 测试文件
- `test_sim.lua` - 简单功能测试（原test_simple.lua）
- `test_cal.lua` - K9标定功能测试（原test_calibration.lua）

## 🔧 功能说明

### K1 - 采样控制
- 启动/停止采样泵（S0继电器）
- 按键按下启动，松开停止

### K5 - 反吹控制
- 执行反吹操作（S1继电器）
- 10秒自动完成

### K9 - 标定控制
- 执行标定操作（S1+S2继电器）
- 30秒自动完成，自动重启采样泵

## 🚀 使用方法

### 1. 启动系统
```lua
-- 主程序自动启动
require("main")
```

### 2. 运行测试
```lua
-- 简单功能测试
require("test_sim")

-- 标定功能测试
require("test_cal")
```

### 3. 手动控制
```lua
local plc = require("plc_controller")
plc.manual_start_sampling()    -- 启动采样
plc.manual_start_backflush()   -- 启动反吹
plc.manual_start_calibration() -- 启动标定
plc.emergency_stop()           -- 紧急停止
```

## 📊 系统状态

- **IDLE**: 空闲状态
- **RUNNING**: 运行状态（采样泵工作）
- **CALIBRATING**: 标定状态
- **BACKFLUSHING**: 反吹状态

## 🛡️ 安全特性

- 功能互锁：标定、反吹、采样不能同时进行
- 超时保护：反吹15秒，标定60秒
- 紧急停止：一键停止所有操作

## 📝 注意事项

1. 文件名已缩短至24字节以下
2. 使用简化的配置管理器避免复杂JSON解析
3. 所有功能都有完整的安全保护
4. 支持手动控制和自动序列控制

---

*本文档描述了采样系统PLC的文件结构和基本使用方法*
