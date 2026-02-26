# PLC配置系统使用说明

## 🎯 系统概述

这是一个专业的PLC配置系统，支持在电脑上生成配置文件，然后上传到设备自动执行。系统包含以下组件：

- **设备端**: Lua脚本，自动加载和执行配置文件
- **电脑端**: Python工具，生成和上传配置文件
- **配置文件**: JSON格式，定义控制序列和参数

## 🚀 快速开始

### 1. 生成配置文件

在电脑上运行配置生成器：

```bash
python plc_config_generator.py
```

这将生成一个 `plc_sequences.json` 配置文件。

### 2. 上传配置文件

使用上传工具将配置文件发送到设备：

```bash
# 串口上传
python upload_config.py plc_sequences.json --serial

# 网络上传
python upload_config.py plc_sequences.json --network --host 192.168.1.100
```

### 3. 设备自动执行

设备开机时会自动：
- 加载配置文件
- 解析控制序列
- 根据配置执行相应的控制逻辑

## 📁 文件结构

```
├── plc_config_manager.lua    # 设备端配置管理器
├── plc_controller.lua        # PLC控制器
├── plc_editor.lua           # PLC编辑器
├── plc_config_generator.py  # 电脑端配置生成器
├── upload_config.py         # 配置文件上传工具
├── plc_sequences.json       # 生成的配置文件
└── README_PLC_Config.md     # 本说明文档
```

## ⚙️ 配置格式

### 基本结构

```json
{
  "version": "1.0",
  "created_time": "2025-08-20T10:00:00",
  "sequences": {
    "sequence_name": {
      "name": "序列名称",
      "description": "序列描述",
      "steps": [...]
    }
  },
  "global_settings": {
    "auto_start": true,
    "default_sequence": "sequence_name",
    "watchdog_timeout": 30000
  }
}
```

### 步骤类型

#### GPIO输出控制
```json
{
  "type": "gpio_output",
  "params": {
    "pin": "s0",
    "state": true,
    "description": "打开S0继电器"
  }
}
```

#### 延时等待
```json
{
  "type": "delay",
  "params": {
    "duration": 5000,
    "description": "延时5秒"
  }
}
```

#### ModbusRTU通信
```json
{
  "type": "modbus_rtu",
  "params": {
    "command": "start_cycle_blow",
    "description": "启动循环反吹"
  }
}
```

#### 条件判断
```json
{
  "type": "condition",
  "params": {
    "condition": "wait_k1",
    "description": "等待K1按下"
  }
}
```

## 🔧 使用方法

### 创建自定义配置

1. 修改 `plc_config_generator.py`
2. 添加新的序列和步骤
3. 运行生成器创建配置文件

### 示例：温度控制序列

```python
# 创建温度控制序列
generator.add_sequence("temp_control", "温度自动控制")
generator.add_step("temp_control", "condition", condition="wait_k1")
generator.add_step("temp_control", "gpio_output", pin="s0", state=True)
generator.add_step("temp_control", "delay", duration=10000)
generator.add_step("temp_control", "gpio_output", pin="s0", state=False)
```

### 上传配置到设备

#### 串口上传
```bash
python upload_config.py plc_sequences.json --serial
```

#### 网络上传
```bash
python upload_config.py plc_sequences.json --network --host 192.168.1.100
```

## 📋 支持的硬件

### 继电器输出
- S0: GPIO 32
- S1: GPIO 33
- S2: GPIO 20
- S3: GPIO 21
- S4: GPIO 16
- S5: GPIO 162
- S6: GPIO 164
- S7: GPIO 160
- S8: GPIO 3
- S9: GPIO 5

### 开关输入
- K1-K4: ADC3
- K5-K8: ADC2

### 温度传感器
- PT1: SPI CS 12
- PT2: SPI CS 129
- PT3: SPI CS 128

## 🔍 故障排除

### 配置文件加载失败
1. 检查JSON格式是否正确
2. 确认文件路径是否正确
3. 查看设备日志输出

### 序列执行异常
1. 检查步骤参数是否正确
2. 确认硬件连接是否正常
3. 查看PLC控制器日志

### 上传失败
1. 检查串口连接
2. 确认网络连接
3. 查看设备是否支持文件接收

## 📚 高级功能

### 动态序列管理
- 支持运行时添加/删除序列
- 支持序列参数动态修改
- 支持序列状态监控

### 条件控制
- 支持开关状态判断
- 支持温度阈值判断
- 支持时间条件判断

### 循环控制
- 支持固定次数循环
- 支持条件循环
- 支持嵌套循环

## 🎨 自定义开发

### 添加新的步骤类型
1. 在 `plc_controller.lua` 中添加新的步骤类型
2. 在 `plc_config_generator.py` 中添加对应的模板
3. 实现步骤执行逻辑

### 扩展硬件支持
1. 添加新的GPIO定义
2. 实现新的通信协议
3. 添加新的传感器支持

## 📞 技术支持

如有问题，请检查：
1. 设备日志输出
2. 配置文件格式
3. 硬件连接状态
4. 软件版本兼容性

## 🔄 版本历史

- v1.0: 基础PLC配置系统
- 支持GPIO、延时、Modbus、条件控制
- 支持配置文件自动加载
- 支持电脑端配置生成和上传
