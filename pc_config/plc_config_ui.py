#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
简易PLC配置可视化工具（PC端）
- 管理序列：新建/重命名/删除
- 管理步骤：添加/编辑/删除/上移/下移
- 步骤类型：gpio_output、delay、modbus_rtu、condition
- 保存/加载配置JSON；串口/网络上传（复用同目录 upload_config.py）

依赖：仅标准库 + 可选 pyserial、requests（上传时才需要）
"""

import json
import os
import tkinter as tk
from tkinter import ttk, filedialog, messagebox, simpledialog


PIN_CHOICES = [f"s{i}" for i in range(10)]
STEP_TYPES = ["gpio_output", "delay", "modbus_rtu", "condition"]


def default_config():
    return {
        "version": "1.0",
        "created_time": "",
        "sequences": {},
        "global_settings": {"auto_start": False, "default_sequence": "", "watchdog_timeout": 30000},
    }


class PLCConfigUI(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("PLC 配置工具")
        self.geometry("1000x640")
        self.minsize(900, 560)

        self.config_data = default_config()
        self.current_sequence_key = None

        self._build_menu()
        self._build_layout()
        self._refresh_sequences()

    # UI 构建
    def _build_menu(self):
        menubar = tk.Menu(self)
        file_menu = tk.Menu(menubar, tearoff=0)
        file_menu.add_command(label="新建配置", command=self.on_new_config)
        file_menu.add_command(label="打开配置...", command=self.on_load)
        file_menu.add_command(label="保存配置", command=self.on_save)
        file_menu.add_command(label="另存为...", command=self.on_save_as)
        file_menu.add_separator()
        file_menu.add_command(label="退出", command=self.destroy)
        menubar.add_cascade(label="文件", menu=file_menu)

        deploy_menu = tk.Menu(menubar, tearoff=0)
        deploy_menu.add_command(label="串口上传", command=self.on_upload_serial)
        deploy_menu.add_command(label="网络上传", command=self.on_upload_network)
        menubar.add_cascade(label="部署", menu=deploy_menu)

        self.config(menu=menubar)

    def _build_layout(self):
        root = ttk.Frame(self)
        root.pack(fill=tk.BOTH, expand=True)

        # 左：序列列表
        left = ttk.Frame(root)
        left.pack(side=tk.LEFT, fill=tk.Y, padx=8, pady=8)

        ttk.Label(left, text="序列").pack(anchor=tk.W)
        self.seq_list = tk.Listbox(left, width=28, exportselection=False)
        self.seq_list.pack(fill=tk.Y, expand=False)
        self.seq_list.bind("<<ListboxSelect>>", self.on_select_sequence)

        seq_btns = ttk.Frame(left)
        seq_btns.pack(fill=tk.X, pady=6)
        ttk.Button(seq_btns, text="新建", command=self.on_add_sequence).pack(side=tk.LEFT)
        ttk.Button(seq_btns, text="重命名", command=self.on_rename_sequence).pack(side=tk.LEFT, padx=6)
        ttk.Button(seq_btns, text="删除", command=self.on_delete_sequence).pack(side=tk.LEFT)

        # 中：步骤列表
        mid = ttk.Frame(root)
        mid.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=8, pady=8)

        ttk.Label(mid, text="步骤").pack(anchor=tk.W)
        self.step_list = tk.Listbox(mid, exportselection=False)
        self.step_list.pack(fill=tk.BOTH, expand=True)

        step_btns = ttk.Frame(mid)
        step_btns.pack(fill=tk.X, pady=6)
        ttk.Button(step_btns, text="添加", command=self.on_add_step).pack(side=tk.LEFT)
        ttk.Button(step_btns, text="编辑", command=self.on_edit_step).pack(side=tk.LEFT, padx=6)
        ttk.Button(step_btns, text="删除", command=self.on_delete_step).pack(side=tk.LEFT)
        ttk.Button(step_btns, text="上移", command=lambda: self.on_move_step(-1)).pack(side=tk.LEFT, padx=6)
        ttk.Button(step_btns, text="下移", command=lambda: self.on_move_step(1)).pack(side=tk.LEFT)

        # 右：全局设置
        right = ttk.Frame(root)
        right.pack(side=tk.LEFT, fill=tk.Y, padx=8, pady=8)

        ttk.Label(right, text="全局设置").pack(anchor=tk.W)
        self.var_auto = tk.BooleanVar(value=False)
        ttk.Checkbutton(right, text="开机自动启动", variable=self.var_auto, command=self.on_global_changed).pack(anchor=tk.W)
        ttk.Label(right, text="默认序列").pack(anchor=tk.W, pady=(12, 0))
        self.default_seq_cb = ttk.Combobox(right, state="readonly")
        self.default_seq_cb.pack(fill=tk.X)
        self.default_seq_cb.bind("<<ComboboxSelected>>", lambda e: self.on_set_default())

        ttk.Label(right, text="看门狗(ms)").pack(anchor=tk.W, pady=(12, 0))
        self.var_wdt = tk.StringVar(value="30000")
        ttk.Entry(right, textvariable=self.var_wdt).pack(fill=tk.X)
        ttk.Button(right, text="应用", command=self.on_global_changed).pack(pady=8)

        ttk.Separator(right, orient=tk.HORIZONTAL).pack(fill=tk.X, pady=8)
        ttk.Button(right, text="保存配置", command=self.on_save).pack(fill=tk.X)
        ttk.Button(right, text="打开配置...", command=self.on_load).pack(fill=tk.X, pady=6)
        ttk.Button(right, text="串口上传", command=self.on_upload_serial).pack(fill=tk.X)
        ttk.Button(right, text="网络上传", command=self.on_upload_network).pack(fill=tk.X, pady=6)

    # 事件处理
    def on_new_config(self):
        if not self._confirm_discard_changes():
            return
        self.config_data = default_config()
        self.current_sequence_key = None
        self._refresh_sequences()
        self._refresh_steps()

    def on_load(self):
        path = filedialog.askopenfilename(title="打开配置", filetypes=[["JSON", "*.json"], ["All", "*.*"]])
        if not path:
            return
        try:
            with open(path, "r", encoding="utf-8") as f:
                self.config_data = json.load(f)
            self.current_sequence_key = None
            self._refresh_sequences()
            self._refresh_steps()
            messagebox.showinfo("提示", f"已加载: {os.path.basename(path)}")
        except Exception as e:
            messagebox.showerror("错误", f"加载失败: {e}")

    def on_save(self):
        # 若没有路径，执行另存为
        return self.on_save_as()

    def on_save_as(self):
        path = filedialog.asksaveasfilename(title="保存配置", defaultextension=".json", filetypes=[["JSON", "*.json"], ["All", "*.*"]])
        if not path:
            return
        try:
            # 同步全局设置
            self.config_data.setdefault("global_settings", {})
            self.config_data["global_settings"]["auto_start"] = bool(self.var_auto.get())
            self.config_data["global_settings"]["default_sequence"] = self.default_seq_cb.get()
            self.config_data["global_settings"]["watchdog_timeout"] = int(self.var_wdt.get() or 30000)

            with open(path, "w", encoding="utf-8") as f:
                json.dump(self.config_data, f, ensure_ascii=False, indent=2)
            messagebox.showinfo("提示", f"保存成功: {os.path.basename(path)}")
        except Exception as e:
            messagebox.showerror("错误", f"保存失败: {e}")

    def on_upload_serial(self):
        try:
            from pc_config.upload_config import ConfigUploader
        except Exception:
            messagebox.showerror("错误", "缺少上传工具：pc_config/upload_config.py 或 pyserial 库")
            return
        # 先保存到临时文件
        tmp = os.path.abspath("plc_sequences.json")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self._snapshot(), f, ensure_ascii=False, indent=2)
        up = ConfigUploader()
        up.upload_via_serial(tmp)

    def on_upload_network(self):
        try:
            from pc_config.upload_config import ConfigUploader
        except Exception:
            messagebox.showerror("错误", "缺少上传工具：pc_config/upload_config.py 或 requests 库")
            return
        host = simpledialog.askstring("网络上传", "请输入设备IP地址：")
        if not host:
            return
        tmp = os.path.abspath("plc_sequences.json")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self._snapshot(), f, ensure_ascii=False, indent=2)
        up = ConfigUploader()
        up.upload_via_network(tmp, host)

    def on_add_sequence(self):
        name = simpledialog.askstring("新建序列", "请输入序列键名(例如 k9_control)：")
        if not name:
            return
        disp = simpledialog.askstring("显示名称", "请输入序列显示名称(例如 K9控制序列)：", initialvalue="K9控制序列")
        seq = {"name": disp or name, "description": "", "steps": []}
        self.config_data.setdefault("sequences", {})[name] = seq
        self.current_sequence_key = name
        self._refresh_sequences(select_key=name)
        self._refresh_steps()

    def on_rename_sequence(self):
        key = self.current_sequence_key
        if not key:
            return
        new_key = simpledialog.askstring("重命名序列", "新的序列键名：", initialvalue=key)
        if not new_key or new_key == key:
            return
        # 迁移
        self.config_data["sequences"][new_key] = self.config_data["sequences"].pop(key)
        # 更新默认序列
        if self.config_data.get("global_settings", {}).get("default_sequence") == key:
            self.config_data["global_settings"]["default_sequence"] = new_key
        self.current_sequence_key = new_key
        self._refresh_sequences(select_key=new_key)

    def on_delete_sequence(self):
        key = self.current_sequence_key
        if not key:
            return
        if not messagebox.askyesno("确认", f"删除序列 {key} ?"):
            return
        self.config_data["sequences"].pop(key, None)
        if self.config_data.get("global_settings", {}).get("default_sequence") == key:
            self.config_data["global_settings"]["default_sequence"] = ""
        self.current_sequence_key = None
        self._refresh_sequences()
        self._refresh_steps()

    def on_select_sequence(self, _):
        idx = self.seq_list.curselection()
        if not idx:
            return
        key = self.seq_list.get(idx[0]).split(" ", 1)[0]
        self.current_sequence_key = key
        self._refresh_steps()

    def on_add_step(self):
        key = self.current_sequence_key
        if not key:
            return
        dlg = StepDialog(self, title="添加步骤")
        step = dlg.result
        if not step:
            return
        self.config_data["sequences"][key]["steps"].append(step)
        self._refresh_steps()

    def on_edit_step(self):
        key = self.current_sequence_key
        if not key:
            return
        idxs = self.step_list.curselection()
        if not idxs:
            return
        idx = idxs[0]
        cur = self.config_data["sequences"][key]["steps"][idx]
        dlg = StepDialog(self, title="编辑步骤", init_step=cur)
        step = dlg.result
        if not step:
            return
        self.config_data["sequences"][key]["steps"][idx] = step
        self._refresh_steps(select_index=idx)

    def on_delete_step(self):
        key = self.current_sequence_key
        if not key:
            return
        idxs = self.step_list.curselection()
        if not idxs:
            return
        idx = idxs[0]
        self.config_data["sequences"][key]["steps"].pop(idx)
        self._refresh_steps()

    def on_move_step(self, direction):
        key = self.current_sequence_key
        if not key:
            return
        idxs = self.step_list.curselection()
        if not idxs:
            return
        idx = idxs[0]
        steps = self.config_data["sequences"][key]["steps"]
        new_idx = idx + direction
        if 0 <= new_idx < len(steps):
            steps[idx], steps[new_idx] = steps[new_idx], steps[idx]
            self._refresh_steps(select_index=new_idx)

    def on_global_changed(self):
        self.config_data.setdefault("global_settings", {})
        self.config_data["global_settings"]["auto_start"] = bool(self.var_auto.get())
        self.config_data["global_settings"]["default_sequence"] = self.default_seq_cb.get()
        try:
            self.config_data["global_settings"]["watchdog_timeout"] = int(self.var_wdt.get() or 30000)
        except Exception:
            pass

    def on_set_default(self):
        self.on_global_changed()

    # 工具
    def _confirm_discard_changes(self):
        return messagebox.askyesno("确认", "放弃未保存更改？")

    def _refresh_sequences(self, select_key=None):
        self.seq_list.delete(0, tk.END)
        for key, seq in self.config_data.get("sequences", {}).items():
            disp = seq.get("name") or key
            self.seq_list.insert(tk.END, f"{key}  |  {disp}")
        keys = list(self.config_data.get("sequences", {}).keys())
        self.default_seq_cb["values"] = keys
        self.var_auto.set(bool(self.config_data.get("global_settings", {}).get("auto_start", False)))
        self.var_wdt.set(str(self.config_data.get("global_settings", {}).get("watchdog_timeout", 30000)))
        cur_def = self.config_data.get("global_settings", {}).get("default_sequence", "")
        self.default_seq_cb.set(cur_def if cur_def in keys else "")
        # 选中
        if select_key and select_key in keys:
            idx = keys.index(select_key)
            self.seq_list.selection_clear(0, tk.END)
            self.seq_list.selection_set(idx)
            self.seq_list.activate(idx)

    def _refresh_steps(self, select_index=None):
        self.step_list.delete(0, tk.END)
        key = self.current_sequence_key
        if not key:
            return
        steps = self.config_data.get("sequences", {}).get(key, {}).get("steps", [])
        for i, step in enumerate(steps, 1):
            t = step.get("type")
            p = step.get("params", {})
            desc = p.get("description") or self._short_desc(step)
            self.step_list.insert(tk.END, f"{i}. {t}  |  {desc}")
        if select_index is not None and 0 <= select_index < len(steps):
            self.step_list.selection_clear(0, tk.END)
            self.step_list.selection_set(select_index)
            self.step_list.activate(select_index)

    def _short_desc(self, step):
        t = step.get("type")
        p = step.get("params", {})
        if t == "gpio_output":
            return f"{p.get('pin','s0')} -> {'ON' if p.get('state') else 'OFF'}"
        if t == "delay":
            return f"delay {p.get('duration',0)} ms"
        if t == "modbus_rtu":
            return f"modbus {p.get('command','')}"
        if t == "condition":
            return f"cond {p.get('condition','')}"
        return t

    def _snapshot(self):
        # 返回最新配置（包含全局设置同步）
        snap = json.loads(json.dumps(self.config_data))
        snap.setdefault("global_settings", {})
        snap["global_settings"]["auto_start"] = bool(self.var_auto.get())
        snap["global_settings"]["default_sequence"] = self.default_seq_cb.get()
        try:
            snap["global_settings"]["watchdog_timeout"] = int(self.var_wdt.get() or 30000)
        except Exception:
            snap["global_settings"]["watchdog_timeout"] = 30000
        return snap


class StepDialog(tk.Toplevel):
    def __init__(self, parent, title="步骤", init_step=None):
        super().__init__(parent)
        self.transient(parent)
        self.title(title)
        self.resizable(False, False)
        self.result = None

        self.var_type = tk.StringVar(value=(init_step or {}).get("type", STEP_TYPES[0]))
        self.var_desc = tk.StringVar(value=((init_step or {}).get("params", {}).get("description", "")))

        frm = ttk.Frame(self)
        frm.pack(padx=12, pady=12, fill=tk.BOTH, expand=True)

        ttk.Label(frm, text="步骤类型").grid(row=0, column=0, sticky=tk.W)
        cb = ttk.Combobox(frm, values=STEP_TYPES, textvariable=self.var_type, state="readonly")
        cb.grid(row=0, column=1, sticky=tk.EW)
        cb.bind("<<ComboboxSelected>>", lambda e: self._refresh_fields())

        ttk.Label(frm, text="描述").grid(row=1, column=0, sticky=tk.W, pady=(6, 0))
        ttk.Entry(frm, textvariable=self.var_desc).grid(row=1, column=1, sticky=tk.EW, pady=(6, 0))

        self.dynamic = ttk.Frame(frm)
        self.dynamic.grid(row=2, column=0, columnspan=2, sticky=tk.EW, pady=(8, 0))

        btns = ttk.Frame(frm)
        btns.grid(row=3, column=0, columnspan=2, sticky=tk.E, pady=(10, 0))
        ttk.Button(btns, text="确定", command=self.on_ok).pack(side=tk.RIGHT)
        ttk.Button(btns, text="取消", command=self.destroy).pack(side=tk.RIGHT, padx=6)

        frm.columnconfigure(1, weight=1)
        self._refresh_fields(init_step)
        self.grab_set()
        self.wait_window(self)

    def _refresh_fields(self, init_step=None):
        for w in self.dynamic.winfo_children():
            w.destroy()
        t = self.var_type.get()
        self.fields = {}
        if t == "gpio_output":
            ttk.Label(self.dynamic, text="引脚").grid(row=0, column=0, sticky=tk.W)
            pin = tk.StringVar(value=((init_step or {}).get("params", {}).get("pin", PIN_CHOICES[0])))
            cb = ttk.Combobox(self.dynamic, values=PIN_CHOICES, textvariable=pin, state="readonly")
            cb.grid(row=0, column=1, sticky=tk.EW)
            self.fields["pin"] = pin

            ttk.Label(self.dynamic, text="状态").grid(row=1, column=0, sticky=tk.W, pady=(6, 0))
            state = tk.BooleanVar(value=((init_step or {}).get("params", {}).get("state", True)))
            ttk.Checkbutton(self.dynamic, text="打开(ON)", variable=state).grid(row=1, column=1, sticky=tk.W, pady=(6, 0))
            self.fields["state"] = state

        elif t == "delay":
            ttk.Label(self.dynamic, text="时长(ms)").grid(row=0, column=0, sticky=tk.W)
            dur = tk.StringVar(value=str((init_step or {}).get("params", {}).get("duration", 1000)))
            ttk.Entry(self.dynamic, textvariable=dur).grid(row=0, column=1, sticky=tk.EW)
            self.fields["duration"] = dur

        elif t == "modbus_rtu":
            ttk.Label(self.dynamic, text="指令").grid(row=0, column=0, sticky=tk.W)
            cmd = tk.StringVar(value=((init_step or {}).get("params", {}).get("command", "")))
            ttk.Entry(self.dynamic, textvariable=cmd).grid(row=0, column=1, sticky=tk.EW)
            self.fields["command"] = cmd

        elif t == "condition":
            ttk.Label(self.dynamic, text="条件键").grid(row=0, column=0, sticky=tk.W)
            cond = tk.StringVar(value=((init_step or {}).get("params", {}).get("condition", "")))
            ttk.Entry(self.dynamic, textvariable=cond).grid(row=0, column=1, sticky=tk.EW)
            self.fields["condition"] = cond

    def on_ok(self):
        t = self.var_type.get()
        params = {"description": self.var_desc.get()}
        if t == "gpio_output":
            params.update({"pin": self.fields["pin"].get(), "state": bool(self.fields["state"].get())})
        elif t == "delay":
            try:
                params.update({"duration": int(self.fields["duration"].get())})
            except Exception:
                messagebox.showerror("错误", "时长必须为整数")
                return
        elif t == "modbus_rtu":
            params.update({"command": self.fields["command"].get()})
        elif t == "condition":
            params.update({"condition": self.fields["condition"].get()})

        self.result = {"type": t, "params": params}
        self.destroy()


if __name__ == "__main__":
    app = PLCConfigUI()
    app.mainloop()


