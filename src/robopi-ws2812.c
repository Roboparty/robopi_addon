// SPDX-License-Identifier: GPL-3.0
// Copyright (C) 2025-2026 fanxiaobinggit
/* RoboPi2 RK3588S PWM6_M1 WS2812 frame transmitter. */

#include <linux/clk.h>
#include <linux/delay.h>
#include <linux/device.h>
#include <linux/fs.h>
#include <linux/io.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/platform_device.h>
#include <linux/pinctrl/consumer.h>
#include <linux/preempt.h>
#include <linux/uaccess.h>

#define PWM6_PHYS       0xfebd0020
#define PWM_MAP_SIZE    0x10
#define PWM_PERIOD      0x04
#define PWM_DUTY        0x08
#define PWM_CTRL        0x0c

#define LED_COUNT       18
#define FRAME_BYTES     (LED_COUNT * 3)

/* RoboPi2 PWM6 timing validated by the original direct-MMIO backend. */
#define PERIOD_TICKS    18
#define ZERO_TICKS      6
#define ONE_TICKS       12

/* Match the validated RK3588 oneshot sequence used by ws2812_pwm.c. */
#define ONESHOT_CTRL    (BIT(0) | BIT(3) | BIT(5) | BIT(8) | BIT(9) | BIT(16))

static void __iomem *pwm;
static struct device *pwm_dev;
static struct clk *pwm_clk;
static struct clk *pclk;
static struct pinctrl *pwm_pinctrl;
static struct pinctrl_state *pwm_active_state;
static DEFINE_MUTEX(tx_lock);

static int send_frame(const u8 frame[FRAME_BYTES])
{
	unsigned long flags;
	u32 value;
	int byte, bit, timeout;

	local_irq_save(flags);
	preempt_disable();
	writel(PERIOD_TICKS, pwm + PWM_PERIOD);

	for (byte = 0; byte < FRAME_BYTES; byte++) {
		for (bit = 7; bit >= 0; bit--) {
			writel((frame[byte] & BIT(bit)) ? ONE_TICKS : ZERO_TICKS,
			       pwm + PWM_DUTY);
			writel(ONESHOT_CTRL, pwm + PWM_CTRL);
			timeout = 10000;
			do {
				value = readl(pwm + PWM_CTRL);
				cpu_relax();
			} while ((value & BIT(0)) && --timeout);
			if (!timeout) {
				writel(0, pwm + PWM_CTRL);
				preempt_enable();
				local_irq_restore(flags);
				return -ETIMEDOUT;
			}
		}
	}

	writel(0, pwm + PWM_CTRL);
	preempt_enable();
	local_irq_restore(flags);
	udelay(80);
	return 0;
}

static ssize_t ws2812_write(struct file *file, const char __user *buffer,
			    size_t count, loff_t *offset)
{
	u8 frame[FRAME_BYTES];
	int ret;

	if (count != FRAME_BYTES)
		return -EINVAL;
	if (copy_from_user(frame, buffer, sizeof(frame)))
		return -EFAULT;

	if (mutex_lock_interruptible(&tx_lock))
		return -ERESTARTSYS;
	ret = send_frame(frame);
	mutex_unlock(&tx_lock);
	return ret ? ret : count;
}

static const struct file_operations ws2812_fops = {
	.owner = THIS_MODULE,
	.write = ws2812_write,
	.llseek = no_llseek,
};

static struct miscdevice ws2812_misc = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "robopi-ws2812",
	.fops = &ws2812_fops,
	.mode = 0660,
};

static int __init robopi_ws2812_init(void)
{
	int ret;

	pwm_dev = bus_find_device_by_name(&platform_bus_type, NULL,
					  "febd0020.pwm");
	if (!pwm_dev)
		return -ENODEV;

	/*
	 * RoboPi2 DTBs name the PWM6_M1 pinctrl state "active" instead of
	 * the conventional "default", so the PWM platform driver does not
	 * select it automatically.  Select it here to route PWM6 to GPIO4_C1.
	 */
	pwm_pinctrl = pinctrl_get(pwm_dev);
	if (IS_ERR(pwm_pinctrl)) {
		ret = PTR_ERR(pwm_pinctrl);
		pwm_pinctrl = NULL;
		goto err_device;
	}
	pwm_active_state = pinctrl_lookup_state(pwm_pinctrl, PINCTRL_STATE_DEFAULT);
	if (IS_ERR(pwm_active_state))
		pwm_active_state = pinctrl_lookup_state(pwm_pinctrl, "active");
	if (IS_ERR(pwm_active_state)) {
		ret = PTR_ERR(pwm_active_state);
		pwm_active_state = NULL;
		goto err_pinctrl;
	}
	ret = pinctrl_select_state(pwm_pinctrl, pwm_active_state);
	if (ret)
		goto err_pinctrl;

	pwm_clk = clk_get(pwm_dev, "pwm");
	if (IS_ERR(pwm_clk)) {
		ret = PTR_ERR(pwm_clk);
		pwm_clk = NULL;
		goto err_device;
	}
	pclk = clk_get(pwm_dev, "pclk");
	if (IS_ERR(pclk)) {
		ret = PTR_ERR(pclk);
		pclk = NULL;
		goto err_pwm_clk;
	}
	ret = clk_prepare_enable(pclk);
	if (ret)
		goto err_pclk;
	ret = clk_prepare_enable(pwm_clk);
	if (ret)
		goto err_disable_pclk;
	pwm = ioremap(PWM6_PHYS, PWM_MAP_SIZE);
	if (!pwm) {
		ret = -ENOMEM;
		goto err_disable_pwm_clk;
	}
	writel(0, pwm + PWM_CTRL);
	ret = misc_register(&ws2812_misc);
	if (ret)
		goto err_unmap;
	pr_info("robopi_ws2812: PWM6_M1 ready, %d LEDs\n", LED_COUNT);
	return 0;

err_unmap:
	iounmap(pwm);
err_disable_pwm_clk:
	clk_disable_unprepare(pwm_clk);
err_disable_pclk:
	clk_disable_unprepare(pclk);
err_pclk:
	clk_put(pclk);
err_pwm_clk:
	clk_put(pwm_clk);
err_pinctrl:
	pinctrl_put(pwm_pinctrl);
err_device:
	put_device(pwm_dev);
	return ret;
}

static void __exit robopi_ws2812_exit(void)
{
	u8 off[FRAME_BYTES] = { 0 };

	misc_deregister(&ws2812_misc);
	mutex_lock(&tx_lock);
	send_frame(off);
	mutex_unlock(&tx_lock);
	writel(0, pwm + PWM_CTRL);
	iounmap(pwm);
	clk_disable_unprepare(pwm_clk);
	clk_disable_unprepare(pclk);
	clk_put(pclk);
	clk_put(pwm_clk);
	pinctrl_put(pwm_pinctrl);
	put_device(pwm_dev);
	pr_info("robopi_ws2812: stopped\n");
}

module_init(robopi_ws2812_init);
module_exit(robopi_ws2812_exit);
MODULE_LICENSE("GPL");
MODULE_AUTHOR("RoboParty");
MODULE_DESCRIPTION("RoboPi2 PWM6_M1 WS2812 controller");
