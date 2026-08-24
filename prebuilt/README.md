# Prebuilt kernel module

`6.1.99-rt36-rockchip-rk3588/robopi-ws2812.ko` is built against the exact
RoboPi2 Linux 6.1.99-rt36-rockchip-rk3588 headers. Its expected properties are:

```text
architecture: ARM aarch64
vermagic:     6.1.99-rt36-rockchip-rk3588 SMP preempt_rt mod_unload aarch64
```

Rebuild and replace the module whenever the target kernel version,
configuration, or symbol versions change.
