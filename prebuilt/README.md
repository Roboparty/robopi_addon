# Prebuilt kernel module

Modules are built against exact RoboPi target kernels. Expected properties:

## 6.18.51-current-rockchip64

```text
architecture: ARM aarch64
vermagic:     6.18.51-current-rockchip64 SMP preempt_rt mod_unload aarch64
```

Files:

- `6.18.51-current-rockchip64/aic_load_fw.ko`
- `6.18.51-current-rockchip64/aic8800_fdrv.ko` (UGREEN AX300 + Linux 6.18 API patches)
- `6.18.51-current-rockchip64/robopi-ws2812.ko` (`noop_llseek` for 6.12+)

Rebuild and replace modules whenever the target kernel version, configuration,
or symbol versions change. Never force-load a mismatched module.

AIC8800 6.18 source patch: `prebuilt/aic8800-linux-6.18-compat.patch`.
