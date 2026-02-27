# 寄存器使用说明（当前实现）

## 总览
- 寄存器存储容器：`rsptb` 表
  - 头标识：
    - `rsptb[0x01] = {0xFF, 0xFF}`（2 字节）参见 [main.lua](file:///h:/GIT/LUA/air103-plc-3pt-4i-7o-2486-232/main.lua#L27-L33)
    - `rsptb[0x02] = {0x55, 0x55}`（2 字节）参见 [main.lua](file:///h:/GIT/LUA/air103-plc-3pt-4i-7o-2486-232/main.lua#L27-L33)
  - 数据表：
    - `rsptb[0x03]` 与 `rsptb[0x04]` 为字节数组（镜像写入），长度各 2001 字节（索引 0..2000 初始化）参见 [main.lua](file:///h:/GIT/LUA/air103-plc-3pt-4i-7o-2486-232/main.lua#L29-L33)
- 写入入口：`store_to_rsptb(value, data_type, start_byte)` 将值按类型打包为字节并写入 0x03 与 0x04，从 `start_byte` 起按字节顺序写入。参见函数实现与打包类型支持：
  - 打包函数与类型支持（char/uchar/short/ushort/int/uint/ABCD/DCBA/BADC/CDAB/digital）：[main.lua](file:///h:/GIT/LUA/air103-plc-3pt-4i-7o-2486-232/main.lua#L86-L152)
  - 写入实现： [main.lua](file:///h:/GIT/LUA/air103-plc-3pt-4i-7o-2486-232/main.lua#L154-L168)

> 说明：`ABCD/DCBA/BADC/CDAB` 表示 32 位浮点数的字节序；当前实现默认以大端格式打包（`>f`），并根据所选字节序进行转换。

## 温度相关寄存器（PT100 × 3 路）
- 写入位置与来源：见 [temp_manager.lua](file:///h:/GIT/LUA/air103-plc-3pt-4i-7o-2486-232/temp_manager.lua#L55-L74)

| 起始字节 | 长度 | 数据类型 | 含义 | 生产者 |
|---------:|-----:|---------:|------|--------|
| 1        | 4    | ABCD(float) | 通道1 滑动温度（最近20个正常值平均，四舍五入取整后以 float 存储） | temp_manager |
| 5        | 4    | ABCD(float) | 通道2 滑动温度（同上） | temp_manager |
| 9        | 4    | ABCD(float) | 通道3 滑动温度（同上） | temp_manager |
| 13       | 4    | ABCD(float) | 通道1 实时温度 | max31865 → temp_manager |
| 17       | 4    | ABCD(float) | 通道2 实时温度 | max31865 → temp_manager |
| 21       | 4    | ABCD(float) | 通道3 实时温度 | max31865 → temp_manager |

- 规则与异常处理：
  - 实时温度：当采样无效（故障/未插/非法值）时，发布层使用 `999`。存入寄存器时按 `ABCD` 浮点打包。
- 滑动温度：
  - 窗口：最近 20 个“正常数据”（非 999）；异常（999）不计入窗口。
  - 异常容忍：连续异常 ≤ 3 次时忽略，> 3 次时滑动输出置为 `999`。
- 四舍五入：平均值四舍五入为整数后以浮点格式写入（与其他字段统一为 float）。

## 控制与状态

| 起始字节 | 长度 | 数据类型 | 含义 | 生产者 |
|---------:|-----:|---------:|------|--------|
| 25       | 2    | ushort   | 维护标志（维护按钮：按下=1，松开=0） | 按钮中断逻辑 |

- 写入位置与来源：见中断处理与联动逻辑 [main.lua](file:///h:/GIT/LUA/air103-plc-3pt-4i-7o-2486-232/main.lua#L213-L237)

## 按钮与继电器联动（参考）
- 按钮（上拉，按下=低）：启动=GPIO2，标定=GPIO3，维护=GPIO6，反吹=GPIO7
- 中断模式：双沿（BOTH）+ 防抖（200ms）+ 中断延迟读取（50ms）
- 联动规则（按优先级）：
  1. 标定+反吹：泵=开（GPIO8）、原位阀=开（GPIO10）、标定阀=关（GPIO9）
  2. 仅标定：标定阀=开，其余关
  3. 仅启动：泵=开，其余关
  4. 其他：三者全关
- 日志：中文单行输出“按键联动 …”参见 [main.lua](file:///h:/GIT/LUA/air103-plc-3pt-4i-7o-2486-232/main.lua#L232-L236)

> 备注：报警输出 GPIO5 与寄存器目前未联动，如需映射报警状态至寄存器，请给出地址规划。

## 字节序与读取约定
- 浮点字节序：
  - `ABCD`：高位在前（大端序），函数内部使用 `>f` 打包；`DCBA/BADC/CDAB` 通过字节交换实现。
- 读取建议：
  - 对于温度值（起始 1/5/9/13/17/21）：从起始字节读取 4 字节，按配置的字节序解释为 IEEE754 float。
  - 对于维护标志（起始 25）：读取 2 字节按无符号 16 位整数解释（0/1）。

## 预留与扩展
- 预留范围建议：
  - 27..64：联动输出状态/告警/运行计数等
  - 65..128：PID 参数/目标温度/配置项
  - 129..256：扩展通道与扩展功能
- 若需对接上位机协议，请给出地址表与数据类型需求，我将按上述写入工具函数统一实现并更新本文档。

---

最后更新：请以以下代码位置为准核对实现：
- 寄存器初始化与写入工具：[main.lua:L24-L33](file:///h:/GIT/LUA/air103-plc-3pt-4i-7o-2486-232/main.lua#L24-L33)、[main.lua:L86-L168](file:///h:/GIT/LUA/air103-plc-3pt-4i-7o-2486-232/main.lua#L86-L168)
- 温度写入位置：[temp_manager.lua:L55-L74](file:///h:/GIT/LUA/air103-plc-3pt-4i-7o-2486-232/temp_manager.lua#L55-L74)
- 按钮与维护标志写入位置：[main.lua:L213-L237](file:///h:/GIT/LUA/air103-plc-3pt-4i-7o-2486-232/main.lua#L213-L237)
