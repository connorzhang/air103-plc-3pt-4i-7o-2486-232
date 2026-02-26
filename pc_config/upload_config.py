#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PLC配置文件上传工具
支持通过串口或网络上传配置文件到设备
"""

import os
import sys
import time
import argparse
from pathlib import Path

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print("❌ 需要安装 pyserial 库: pip install pyserial")
    sys.exit(1)

class ConfigUploader:
    def __init__(self):
        self.serial_port = None
        self.baudrate = 115200
        
    def list_serial_ports(self):
        """列出可用的串口"""
        ports = serial.tools.list_ports.comports()
        if not ports:
            print("❌ 未找到可用的串口")
            return []
        
        print("🔌 可用的串口:")
        for i, port in enumerate(ports):
            print(f"  {i+1}. {port.device} - {port.description}")
        
        return ports
    
    def connect_serial(self, port_name):
        """连接串口"""
        try:
            self.serial_port = serial.Serial(
                port=port_name,
                baudrate=self.baudrate,
                timeout=5,
                write_timeout=5
            )
            print(f"✅ 串口连接成功: {port_name}")
            return True
        except Exception as e:
            print(f"❌ 串口连接失败: {e}")
            return False
    
    def disconnect_serial(self):
        """断开串口连接"""
        if self.serial_port and self.serial_port.is_open:
            self.serial_port.close()
            print("🔌 串口连接已断开")
    
    def send_file(self, file_path, target_path="/plc_sequences.json"):
        """通过串口发送文件"""
        if not self.serial_port or not self.serial_port.is_open:
            print("❌ 串口未连接")
            return False
        
        try:
            # 读取文件内容
            with open(file_path, 'rb') as f:
                file_content = f.read()
            
            file_size = len(file_content)
            print(f"📁 文件大小: {file_size} 字节")
            
            # 发送文件头
            header = f"FILE_UPLOAD:{target_path}:{file_size}\n"
            self.serial_port.write(header.encode())
            time.sleep(0.1)
            
            # 等待设备确认
            response = self.serial_port.readline().decode().strip()
            if "READY" not in response:
                print(f"❌ 设备未准备好接收文件: {response}")
                return False
            
            # 发送文件内容
            print("📤 正在上传文件...")
            self.serial_port.write(file_content)
            
            # 等待上传完成确认
            response = self.serial_port.readline().decode().strip()
            if "SUCCESS" in response:
                print("✅ 文件上传成功!")
                return True
            else:
                print(f"❌ 文件上传失败: {response}")
                return False
                
        except Exception as e:
            print(f"❌ 文件上传异常: {e}")
            return False
    
    def upload_via_serial(self, config_file):
        """通过串口上传配置"""
        print("🔌 串口上传模式")
        
        # 列出可用串口
        ports = self.list_serial_ports()
        if not ports:
            return False
        
        # 选择串口
        try:
            choice = int(input("\n请选择串口 (输入序号): ")) - 1
            if choice < 0 or choice >= len(ports):
                print("❌ 无效的选择")
                return False
            
            selected_port = ports[choice].device
        except ValueError:
            print("❌ 请输入有效的数字")
            return False
        
        # 连接串口
        if not self.connect_serial(selected_port):
            return False
        
        try:
            # 上传文件
            success = self.send_file(config_file)
            return success
        finally:
            self.disconnect_serial()
    
    def upload_via_network(self, config_file, host, port=80):
        """通过网络上传配置（需要设备支持HTTP服务器）"""
        print("🌐 网络上传模式")
        print(f"目标设备: {host}:{port}")
        
        try:
            import requests
            
            # 检查文件是否存在
            if not os.path.exists(config_file):
                print(f"❌ 配置文件不存在: {config_file}")
                return False
            
            # 准备上传数据
            with open(config_file, 'rb') as f:
                files = {'file': (os.path.basename(config_file), f, 'application/json')}
                data = {'path': '/plc_sequences.json'}
                
                # 发送POST请求
                url = f"http://{host}:{port}/upload"
                print(f"📤 正在上传到: {url}")
                
                response = requests.post(url, files=files, data=data, timeout=30)
                
                if response.status_code == 200:
                    print("✅ 文件上传成功!")
                    return True
                else:
                    print(f"❌ 上传失败，状态码: {response.status_code}")
                    print(f"响应: {response.text}")
                    return False
                    
        except ImportError:
            print("❌ 需要安装 requests 库: pip install requests")
            return False
        except Exception as e:
            print(f"❌ 网络上传异常: {e}")
            return False
    
    def create_sample_config(self):
        """创建示例配置文件"""
        sample_config = {
            "version": "1.0",
            "created_time": time.strftime("%Y-%m-%d %H:%M:%S"),
            "sequences": {
                "k1_control": {
                    "name": "K1控制序列",
                    "description": "K1按下后的控制流程",
                    "steps": [
                        {
                            "type": "gpio_output",
                            "params": {
                                "pin": "s0",
                            "state": True,
                                "description": "打开S0保持"
                            }
                        },
                        {
                            "type": "modbus_rtu",
                            "params": {
                                "command": "start_cycle_blow",
                                "description": "启动采样探头循环反吹"
                            }
                        },
                        {
                            "type": "gpio_output",
                            "params": {
                                "pin": "s1",
                                "state": True,
                                "description": "打开S1"
                            }
                        },
                        {
                            "type": "delay",
                            "params": {
                                "duration": 10000,
                                "description": "延时10秒"
                            }
                        },
                        {
                            "type": "gpio_output",
                            "params": {
                                "pin": "s1",
                                "state": False,
                                "description": "关闭S1"
                            }
                        }
                    ]
                }
            },
            "global_settings": {
                "auto_start": True,
                "default_sequence": "k1_control",
                "watchdog_timeout": 30000
            }
        }
        
        # 保存示例配置
        import json
        sample_file = "sample_plc_config.json"
        with open(sample_file, 'w', encoding='utf-8') as f:
            json.dump(sample_config, f, ensure_ascii=False, indent=2)
        
        print(f"✅ 示例配置文件已创建: {sample_file}")
        return sample_file

def main():
    parser = argparse.ArgumentParser(description="PLC配置文件上传工具")
    parser.add_argument("config_file", nargs="?", help="配置文件路径")
    parser.add_argument("--serial", action="store_true", help="使用串口上传")
    parser.add_argument("--network", action="store_true", help="使用网络上传")
    parser.add_argument("--host", help="网络上传的目标主机")
    parser.add_argument("--port", type=int, default=80, help="网络上传的目标端口")
    parser.add_argument("--create-sample", action="store_true", help="创建示例配置文件")
    
    args = parser.parse_args()
    
    uploader = ConfigUploader()
    
    # 创建示例配置
    if args.create_sample:
        config_file = uploader.create_sample_config()
        print(f"示例配置文件已创建: {config_file}")
        return
    
    # 确定配置文件路径
    config_file = args.config_file
    if not config_file:
        # 查找配置文件
        possible_files = ["plc_sequences.json", "sample_plc_config.json"]
        for file in possible_files:
            if os.path.exists(file):
                config_file = file
                break
        
        if not config_file:
            print("❌ 未找到配置文件，请指定路径或使用 --create-sample 创建示例")
            return
    
    # 检查文件是否存在
    if not os.path.exists(config_file):
        print(f"❌ 配置文件不存在: {config_file}")
        return
    
    print(f"📁 配置文件: {config_file}")
    
    # 选择上传方式
    if args.serial:
        success = uploader.upload_via_serial(config_file)
    elif args.network:
        if not args.host:
            print("❌ 网络上传需要指定 --host 参数")
            return
        success = uploader.upload_via_network(config_file, args.host, args.port)
    else:
        # 交互式选择
        print("\n📤 选择上传方式:")
        print("1. 串口上传")
        print("2. 网络上传")
        
        try:
            choice = input("请选择 (1-2): ").strip()
            if choice == "1":
                success = uploader.upload_via_serial(config_file)
            elif choice == "2":
                host = input("请输入目标主机IP: ").strip()
                if host:
                    success = uploader.upload_via_network(config_file, host)
                else:
                    print("❌ 主机IP不能为空")
                    return
            else:
                print("❌ 无效的选择")
                return
        except KeyboardInterrupt:
            print("\n❌ 操作已取消")
            return
    
    if success:
        print("\n🎉 配置文件上传完成!")
        print("设备重启后将自动加载新配置")
    else:
        print("\n❌ 配置文件上传失败")

if __name__ == "__main__":
    main()


