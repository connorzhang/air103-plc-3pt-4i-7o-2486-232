#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PLC配置生成器 - 在电脑上生成PLC配置文件
使用方法：
1. 运行此程序生成配置文件
2. 将生成的JSON文件上传到设备
3. 设备开机自动加载配置执行
"""

import json
import os
from datetime import datetime

class PLCConfigGenerator:
    def __init__(self):
        self.config = {
            "version": "1.0",
            "created_time": datetime.now().isoformat(),
            "sequences": {},
            "global_settings": {
                "auto_start": False,
                "default_sequence": "",
                "watchdog_timeout": 30000
            }
        }
        
        # 预定义的步骤模板
        self.step_templates = {
            "gpio_output": {
                "name": "GPIO输出控制",
                "description": "控制继电器开关",
                "params": {
                    "pin": "s0",
                    "state": True,
                    "description": "继电器控制"
                }
            },
            "delay": {
                "name": "延时等待",
                "description": "等待指定时间",
                "params": {
                    "duration": 1000,
                    "description": "延时时间(毫秒)"
                }
            },
            "modbus_rtu": {
                "name": "ModbusRTU通信",
                "description": "发送Modbus指令",
                "params": {
                    "command": "start_cycle_blow",
                    "description": "Modbus指令"
                }
            },
            "condition": {
                "name": "条件判断",
                "description": "等待条件满足",
                "params": {
                    "condition": "wait_k1",
                    "description": "等待K1按下"
                }
            }
        }
    
    def add_sequence(self, name, description=""):
        """添加新的控制序列"""
        self.config["sequences"][name] = {
            "name": name,
            "description": description,
            "steps": [],
            "created_time": datetime.now().isoformat()
        }
        return name
    
    def add_step(self, sequence_name, step_type, **params):
        """向序列添加步骤"""
        if sequence_name not in self.config["sequences"]:
            raise ValueError(f"序列 {sequence_name} 不存在")
        
        if step_type not in self.step_templates:
            raise ValueError(f"步骤类型 {step_type} 不支持")
        
        # 获取模板并应用自定义参数
        step = self.step_templates[step_type].copy()
        step["type"] = step_type
        
        # 更新参数
        for key, value in params.items():
            if key in step["params"]:
                step["params"][key] = value
        
        self.config["sequences"][sequence_name]["steps"].append(step)
        return len(self.config["sequences"][sequence_name]["steps"])
    
    def set_global_setting(self, key, value):
        """设置全局配置"""
        if key in self.config["global_settings"]:
            self.config["global_settings"][key] = value
        else:
            raise ValueError(f"全局设置 {key} 不支持")
    
    def create_k1_control_sequence(self):
        """创建K1控制序列示例"""
        seq_name = self.add_sequence("k1_control", "K1按下后的控制流程")
        
        self.add_step(seq_name, "gpio_output", pin="s0", state=True, description="打开S0保持")
        self.add_step(seq_name, "modbus_rtu", command="start_cycle_blow", description="启动采样探头循环反吹")
        self.add_step(seq_name, "gpio_output", pin="s1", state=True, description="打开S1")
        self.add_step(seq_name, "delay", duration=10000, description="延时10秒")
        self.add_step(seq_name, "gpio_output", pin="s1", state=False, description="关闭S1")
        
        return seq_name
    
    def create_temperature_control_sequence(self):
        """创建温度控制序列示例"""
        seq_name = self.add_sequence("temp_control", "温度自动控制流程")
        
        self.add_step(seq_name, "condition", condition="wait_k1", description="等待K1按下")
        self.add_step(seq_name, "gpio_output", pin="s0", state=True, description="启动加热")
        self.add_step(seq_name, "delay", duration=5000, description="延时5秒")
        self.add_step(seq_name, "gpio_output", pin="s0", state=False, description="停止加热")
        
        return seq_name
    
    def create_industrial_process_sequence(self):
        """创建工业流程序列示例"""
        seq_name = self.add_sequence("industrial_process", "完整的工业控制流程")
        
        # 启动阶段
        self.add_step(seq_name, "gpio_output", pin="s0", state=True, description="启动主电源")
        self.add_step(seq_name, "delay", duration=2000, description="延时2秒")
        self.add_step(seq_name, "modbus_rtu", command="start_cycle_blow", description="启动系统")
        
        # 预热阶段
        self.add_step(seq_name, "gpio_output", pin="s1", state=True, description="启动预热")
        self.add_step(seq_name, "delay", duration=10000, description="延时10秒")
        self.add_step(seq_name, "gpio_output", pin="s1", state=False, description="预热完成")
        
        # 主工作阶段
        self.add_step(seq_name, "gpio_output", pin="s2", state=True, description="启动主工作")
        self.add_step(seq_name, "delay", duration=30000, description="延时30秒")
        
        # 冷却阶段
        self.add_step(seq_name, "gpio_output", pin="s2", state=False, description="停止主工作")
        self.add_step(seq_name, "gpio_output", pin="s3", state=True, description="启动冷却")
        self.add_step(seq_name, "delay", duration=15000, description="延时15秒")
        self.add_step(seq_name, "gpio_output", pin="s3", state=False, description="冷却完成")
        
        # 清理阶段
        self.add_step(seq_name, "modbus_rtu", command="stop_cycle_blow", description="停止系统")
        self.add_step(seq_name, "gpio_output", pin="s0", state=False, description="关闭主电源")
        
        return seq_name
    
    def save_config(self, filename="plc_sequences.json"):
        """保存配置到JSON文件"""
        with open(filename, 'w', encoding='utf-8') as f:
            json.dump(self.config, f, ensure_ascii=False, indent=2)
        
        print(f"✅ 配置文件已保存: {filename}")
        return filename
    
    def print_config_summary(self):
        """打印配置摘要"""
        print("\n" + "="*50)
        print("📋 PLC配置摘要")
        print("="*50)
        print(f"版本: {self.config['version']}")
        print(f"创建时间: {self.config['created_time']}")
        print(f"序列数量: {len(self.config['sequences'])}")
        
        for name, seq in self.config["sequences"].items():
            print(f"\n🔧 序列: {seq['name']}")
            print(f"   描述: {seq['description']}")
            print(f"   步骤数: {len(seq['steps'])}")
            
            for i, step in enumerate(seq['steps'], 1):
                print(f"   步骤{i}: {step['name']} - {step['params']['description']}")
        
        print(f"\n⚙️  全局设置:")
        for key, value in self.config["global_settings"].items():
            print(f"   {key}: {value}")
        print("="*50)

def main():
    """主函数 - 演示配置生成"""
    print("🚀 PLC配置生成器启动")
    
    # 创建配置生成器
    generator = PLCConfigGenerator()
    
    # 创建示例序列
    print("\n📝 创建示例序列...")
    generator.create_k1_control_sequence()
    generator.create_temperature_control_sequence()
    generator.create_industrial_process_sequence()
    
    # 设置全局配置
    generator.set_global_setting("auto_start", True)
    generator.set_global_setting("default_sequence", "k1_control")
    
    # 显示配置摘要
    generator.print_config_summary()
    
    # 保存配置文件
    filename = generator.save_config()
    
    print(f"\n🎯 使用说明:")
    print(f"1. 配置文件已生成: {filename}")
    print(f"2. 将此文件上传到设备的根目录")
    print(f"3. 设备开机时会自动加载并执行配置")
    print(f"4. 可以修改此Python程序来生成不同的配置")
    
    # 显示上传方法
    print(f"\n📤 上传方法:")
    print(f"- 通过串口工具上传文件")
    print(f"- 通过网络工具上传文件")
    print(f"- 通过SD卡复制文件")
    
    return filename

if __name__ == "__main__":
    main()


