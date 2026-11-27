# stylus-fix-old：旧内核基线（只修断流，不叠新特性）

这个分支存在的目的：**把「笔一动蓝牙/音频断流」的修复和 main 上的一堆改动隔离开**，
方便二分定位，也方便刷回接近原厂的行为。

## 构建参数（workflow_dispatch 时手动指定）

| 参数 | 值 | 含义 |
| --- | --- | --- |
| `source_branch` | **`nabu-w-oss`** | 最接近原厂的 4.14.180 基线树（无 KSU/SUSFS） |
| `perf_overlay` | **false** | 不叠加 BBR/BFQ/SCHED_DEBUG 那套 |
| `autosleep_default` | **false** | 不打 autosleep 默认 mem 补丁 |
| `localversion` | `-perf` | 保持与原厂一致的 release 命名 |

结果 = 原厂 4.14.180 行为 + 本分支上的 stylus 补丁。

## 说明：为什么不用 `nabu-v-oss`

上游 `nabu-v-oss` 是「基线源码快照」，**没有 `recovery/` 目录**（无 BUILD_PROFILE /
profile-reference.config / build-recovery.sh），本流水线的构建脚本无法直接跑；
要用它得另外补一套 defconfig 与打包逻辑，属于额外工作，等确认需要再做。

## 待办

- [ ] 收到 `stylus-diag.txt`（A 静置 / B 写字 两段）后落地 P1（printk 降级）/ P2（IRQ 亲和）/ P3（SPI 降频）
- [ ] 每落地一个补丁就在本分支跑一次 Actions，出包对比