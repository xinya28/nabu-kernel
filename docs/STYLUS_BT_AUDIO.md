# 手写笔 + 蓝牙/音频断流：现象、假设、取证与补丁计划

> 分支：`stylus-bt-audio`（从 `main` 切出，构建参数与 main 相同，只是多了本文件与取证脚本）

## 1. 这台机器上相关链路

| 部件 | 走线 / 驱动 | 备注 |
| --- | --- | --- |
| 触控 + 手写笔 | Novatek **NT36523**，SPI → `nt36523_touch.ko`（`nt36xxx.o`） | 笔数据不是独立设备，而是同一帧 SPI 里的 14 字节 pen packet，240 Hz |
| 蓝牙 | WCN3990，HS-UART（`hci_qca` + `serial_msm_geni`） | 与音频共用 ADSP 侧资源 |
| 音频 | ADSP（`audio_dlkm` / `q6_dlkm` / `wcd_dlkm`） | 断流表现为 a2dp 卡顿、Speaker 爆音 |

三者共同点：**都对 CPU 唤醒延迟和总线争用敏感**。笔以 240 Hz 触发 SPI 中断（每帧几 KB DMA），
如果这一路中断和 BT 的 UART 中断、ADSP 的 mailbox 中断落在同一个 CPU 上，或驱动在中断上下文里
打印/睡眠，就会出现“一动笔，蓝牙音乐就断续”的典型现象。

## 2. 优先怀疑顺序（按经验命中率）

1. **nt36xxx 中断上下文里的日志/延时**：`pr_info`/`pr_err` 在 240 Hz 路径上会把 printk 变成瓶颈
   （尤其 `CONFIG_LOG_BUF_SHIFT` 大、串口 console 未关时），直接拖慢同 CPU 上的 UART 中断。
2. **IRQ 亲和性**：touch SPI 与 BT UART 的中断落在同一 cluster/同一 CPU。
3. **bus/DDR 投票**：笔模式把 SPI 时钟拉高（如 12 MHz→25 MHz），若 QUP 与 UART 共用同一 QUP 核，
   会出现 FIFO overrun。
4. **CPU 频率/调度**：`performance` governor 下一般不会，但 `msm_performance` 的 input boost 若把
   小核拉满、把音频线程挤到大核，也可能抖。
5. **ADSP 侧**：`audio_dlkm` 的 buffer 太小 + 笔中断导致 miss deadline。

## 3. 先取证（这一步不做，任何补丁都是猜）

```bash
adb push scripts/ondevice-stylus-diag.sh /data/local/tmp/
adb shell su -c sh /data/local/tmp/ondevice-stylus-diag.sh > stylus-diag.txt
```

脚本会在**不插笔 / 插笔写字**两个阶段分别采样：`/proc/interrupts` 增量、每 CPU 的
`/proc/stat` 占用、`top -H`、`dmesg` 过滤、`dumpsys audio`/`bluetooth_manager`、
`logcat` 里的 `underrun`/`a2dp`/`bt` 关键字。两份对比就能定位是 1/2/3/4/5 里的哪一个。

## 4. 补丁计划（拿到日志后按序落地，每个都可单独回滚）

| # | 改动 | 风险 | 预期 |
| --- | --- | --- | --- |
| P1 | `nt36xxx`：笔路径 `pr_info`→`pr_debug`，去掉中断里的 `udelay`/`msleep` | 极低 | 消除 printk 抖动 |
| P2 | 给 touch SPI IRQ 设 `irq_set_affinity_hint()` 到大核，BT UART IRQ 绑到另一颗 | 低 | 中断不再互相抢占 |
| P3 | 笔模式 SPI 时钟降到 12 MHz（若 25 MHz 时出现 FIFO overrun） | 低 | 笔跟手略降，换取不抢总线 |
| P4 | ADSP 音频 buffer 加大（`audio_dlkm` 侧，需改 vendor 模块，不在内核） | 中 | 抗抖动 |

P1/P2/P3 都可以在**内核源码**里改，P4 属于 vendor 模块（换内核改不了）。

## 5. 当前状态

- 分支已建：`stylus-bt-audio`，基于 `main`（4.14.180-perf + KSU/SUSFS + autosleep 默认 mem）
- 待办：拿到 `stylus-diag.txt` → 落地 P1/P2/P3 → 在该分支跑 Actions 出包
