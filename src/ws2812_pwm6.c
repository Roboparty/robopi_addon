// RK3588S PWM6_M1 (GPIO4_C1) experimental WS2812 controller, 18 LEDs.
// Target: pwm@febd0020, 24 MHz clock, /sys/class/pwm/pwmchip2.
// Build: gcc -O3 -Wall -Wextra -o ws2812_pwm6 ws2812_pwm6.c -lm
// Run:   sudo roboparty-ws2812 <off|on|solid|flash|chase|rainbow|demo> [args]
//
// This userspace PWM oneshot backend is experimental. Scope validation is
// required for each board/LED combination; it is not enabled automatically.

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <sched.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

#define LED_COUNT       18
#define FRAME_BYTES     (LED_COUNT * 3)
#define PWM6_ADDR       0xfebd0020u
#define PWMCHIP_DIR     "/sys/class/pwm/pwmchip2"
#define PWM_DIR         PWMCHIP_DIR "/pwm0"

#define PWM_PERIOD      0x04
#define PWM_DUTY        0x08
#define PWM_CTRL        0x0c

#define PWM_ENABLE      (1u << 0)
#define PWM_DUTY_POS    (1u << 3)
#define PWM_OUT_L       (1u << 5)
#define PWM_LP_DIS      (1u << 8)
#define PWM_SCALED_CLK  (1u << 9)
#define PWM_SCALE_1     (1u << 16)
#define ONESHOT_CTRL    (PWM_ENABLE | PWM_DUTY_POS | PWM_OUT_L | \
                         PWM_LP_DIS | PWM_SCALED_CLK | PWM_SCALE_1)

static volatile uint32_t *pwm;
static volatile sig_atomic_t running = 1;
static int pwm_exported_by_us;
static uint32_t period_ticks = 30; // 24 MHz: 1.25 us
static uint32_t zero_ticks = 8;    // 0.333 us high
static uint32_t one_ticks = 19;    // 0.792 us high

static void on_signal(int sig) { (void)sig; running = 0; }

static int write_text(const char *path, const char *text) {
    int fd = open(path, O_WRONLY);
    if (fd < 0) return -1;
    ssize_t len = (ssize_t)strlen(text);
    ssize_t n = write(fd, text, (size_t)len);
    int saved = errno;
    close(fd);
    errno = saved;
    return n == len ? 0 : -1;
}

static int wait_for_path(const char *path) {
    for (int i = 0; i < 100; ++i) {
        if (access(path, F_OK) == 0) return 0;
        usleep(10000);
    }
    return -1;
}

static int pwm_clock_on(void) {
    if (access(PWM_DIR, F_OK) != 0) {
        if (write_text(PWMCHIP_DIR "/export", "0") != 0 && errno != EBUSY) {
            perror("export pwmchip2/pwm0");
            return -1;
        }
        pwm_exported_by_us = 1;
    }
    if (wait_for_path(PWM_DIR "/period") != 0) {
        fprintf(stderr, "PWM sysfs interface did not appear\n");
        return -1;
    }

    // Let the kernel enable the PWM clock and select PWM6_M1 pinctrl.
    write_text(PWM_DIR "/enable", "0");
    // Clear a duty left by an earlier sysfs user before reducing the period.
    // The board PWM driver has already been validated with this 100 ms
    // bootstrap period. MMIO replaces it before any LED data is sent.
    // A newly exported channel can report period=0 and reject even duty=0
    // with EINVAL. That state is safe: set the period first. For a channel
    // left configured by an earlier user, clearing duty succeeds and allows
    // the period to be changed safely.
    if (write_text(PWM_DIR "/duty_cycle", "0") != 0 && errno != EINVAL) {
        perror("clear bootstrap duty");
        return -1;
    }
    if (write_text(PWM_DIR "/period", "100000000") != 0) { perror("set bootstrap period"); return -1; }
    if (write_text(PWM_DIR "/duty_cycle", "50000000") != 0) { perror("set bootstrap duty"); return -1; }
    if (write_text(PWM_DIR "/enable", "1") != 0) { perror("enable pwmchip2/pwm0"); return -1; }
    return 0;
}

static int map_pwm(void) {
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) { perror("open /dev/mem"); return -1; }
    uintptr_t page = PWM6_ADDR & ~0xfffu;
    void *base = mmap(NULL, 0x1000, PROT_READ | PROT_WRITE,
                      MAP_SHARED, fd, (off_t)page);
    close(fd);
    if (base == MAP_FAILED) { perror("mmap PWM6"); return -1; }
    pwm = (volatile uint32_t *)((uintptr_t)base + (PWM6_ADDR & 0xfff));
    pwm[PWM_CTRL / 4] = 0;
    return 0;
}

static void pwm_clock_off(void) {
    if (pwm) pwm[PWM_CTRL / 4] = 0;
    write_text(PWM_DIR "/enable", "0");
    if (pwm_exported_by_us) write_text(PWMCHIP_DIR "/unexport", "0");
}

static int send_frame(const uint8_t frame[FRAME_BYTES]) {
    pwm[PWM_PERIOD / 4] = period_ticks;
    for (int i = 0; i < FRAME_BYTES; ++i) {
        for (int bit = 7; bit >= 0; --bit) {
            pwm[PWM_DUTY / 4] = (frame[i] & (1u << bit)) ? one_ticks : zero_ticks;
            __sync_synchronize();
            pwm[PWM_CTRL / 4] = ONESHOT_CTRL;
            int timeout = 100000;
            while ((pwm[PWM_CTRL / 4] & PWM_ENABLE) && --timeout) { }
            if (!timeout) {
                fprintf(stderr, "PWM6 oneshot timeout; clock or pinmux is unavailable\n");
                pwm[PWM_CTRL / 4] = 0;
                return -1;
            }
        }
    }
    pwm[PWM_CTRL / 4] = 0;
    usleep(80); // WS2812 reset/latch, >50 us
    return 0;
}

static void fill(uint8_t *f, int r, int g, int b) {
    for (int i = 0; i < LED_COUNT; ++i) {
        f[i * 3] = (uint8_t)g;     // WS2812 byte order: GRB
        f[i * 3 + 1] = (uint8_t)r;
        f[i * 3 + 2] = (uint8_t)b;
    }
}

static int byte_arg(const char *s, const char *name) {
    char *end;
    long n = strtol(s, &end, 10);
    if (*s == '\0' || *end != '\0' || n < 0 || n > 255) {
        fprintf(stderr, "%s must be 0..255: %s\n", name, s);
        exit(2);
    }
    return (int)n;
}

static int int_arg(const char *s, int min, int max, const char *name) {
    char *end;
    long n = strtol(s, &end, 10);
    if (*s == '\0' || *end != '\0' || n < min || n > max) {
        fprintf(stderr, "%s must be %d..%d: %s\n", name, min, max, s);
        exit(2);
    }
    return (int)n;
}

static void hsv(float h, float v, uint8_t *r, uint8_t *g, uint8_t *b) {
    float x = h * 6.0f;
    int sector = (int)x;
    float f = x - sector, p = 0, q = v * (1 - f), t = v * f;
    float rr, gg, bb;
    switch (sector % 6) {
        case 0: rr=v; gg=t; bb=p; break; case 1: rr=q; gg=v; bb=p; break;
        case 2: rr=p; gg=v; bb=t; break; case 3: rr=p; gg=q; bb=v; break;
        case 4: rr=t; gg=p; bb=v; break; default: rr=v; gg=p; bb=q; break;
    }
    *r=(uint8_t)(rr*255); *g=(uint8_t)(gg*255); *b=(uint8_t)(bb*255);
}

static void usage(const char *p) {
    printf("RK3588S PWM6_M1 WS2812 controller (%d LEDs)\n", LED_COUNT);
    printf("Usage:\n");
    printf("  sudo %s off\n", p);
    printf("  sudo %s on [R G B]                 default: 48 48 48\n", p);
    printf("  sudo %s solid R G B\n", p);
    printf("  sudo %s flash R G B [ms] [count]   count=0: until Ctrl+C\n", p);
    printf("  sudo %s chase R G B [ms] [width]\n", p);
    printf("  sudo %s rainbow [ms]\n", p);
    printf("  sudo %s demo                       8-second test, then off\n", p);
}

int main(int argc, char **argv) {
    if (argc < 2 || !strcmp(argv[1], "help") || !strcmp(argv[1], "--help")) {
        usage(argv[0]); return argc < 2 ? 2 : 0;
    }
    if (geteuid() != 0) { fprintf(stderr, "Run with sudo.\n"); return 1; }
    signal(SIGINT, on_signal); signal(SIGTERM, on_signal);
    if (pwm_clock_on() || map_pwm()) { pwm_clock_off(); return 1; }

    struct sched_param sp = { .sched_priority = 80 };
    sched_setscheduler(0, SCHED_FIFO, &sp);
    setpriority(PRIO_PROCESS, 0, -20);

    uint8_t f[FRAME_BYTES] = {0};
    const char *cmd = argv[1];
    int rc = 0;
    if (!strcmp(cmd, "off")) {
        rc = send_frame(f);
    } else if (!strcmp(cmd, "on") || !strcmp(cmd, "solid")) {
        int r=48, g=48, b=48;
        if (!strcmp(cmd, "solid") || argc >= 5) {
            if (argc < 5) { usage(argv[0]); rc=2; goto out; }
            r=byte_arg(argv[2],"R"); g=byte_arg(argv[3],"G"); b=byte_arg(argv[4],"B");
        }
        fill(f,r,g,b); rc=send_frame(f);
    } else if (!strcmp(cmd, "flash")) {
        if (argc < 5) { usage(argv[0]); rc=2; goto out; }
        int r=byte_arg(argv[2],"R"), g=byte_arg(argv[3],"G"), b=byte_arg(argv[4],"B");
        int ms=argc>5?int_arg(argv[5],10,60000,"ms"):300;
        int count=argc>6?int_arg(argv[6],0,1000000,"count"):0;
        for (int n=0; running && (!count || n<count); ++n) {
            fill(f,r,g,b); if (send_frame(f)) { rc=1; break; } usleep(ms*1000);
            memset(f,0,sizeof(f)); if (send_frame(f)) { rc=1; break; } usleep(ms*1000);
        }
    } else if (!strcmp(cmd, "chase")) {
        if (argc < 5) { usage(argv[0]); rc=2; goto out; }
        int r=byte_arg(argv[2],"R"), g=byte_arg(argv[3],"G"), b=byte_arg(argv[4],"B");
        int ms=argc>5?int_arg(argv[5],10,60000,"ms"):70;
        int width=argc>6?int_arg(argv[6],1,LED_COUNT,"width"):3;
        for (int pos=0; running; pos=(pos+1)%LED_COUNT) {
            memset(f,0,sizeof(f));
            for (int j=0;j<width;++j) { int i=(pos-j+LED_COUNT)%LED_COUNT; float v=1.0f-(float)j/(width+1); f[i*3]=g*v; f[i*3+1]=r*v; f[i*3+2]=b*v; }
            if (send_frame(f)) { rc=1; break; } usleep(ms*1000);
        }
    } else if (!strcmp(cmd, "rainbow")) {
        int ms=argc>2?int_arg(argv[2],10,60000,"ms"):40;
        for (int phase=0; running; phase=(phase+1)%360) {
            for (int i=0;i<LED_COUNT;++i) { uint8_t r,g,b; hsv(fmodf(phase/360.0f+i/(float)LED_COUNT,1),0.25f,&r,&g,&b); f[i*3]=g; f[i*3+1]=r; f[i*3+2]=b; }
            if (send_frame(f)) { rc=1; break; } usleep(ms*1000);
        }
    } else if (!strcmp(cmd, "demo")) {
        const int colors[3][3]={{48,0,0},{0,48,0},{0,0,48}};
        for(int c=0;c<3 && running;++c){fill(f,colors[c][0],colors[c][1],colors[c][2]);send_frame(f);usleep(500000);}
        for(int pos=0;pos<LED_COUNT*2 && running;++pos){memset(f,0,sizeof(f));int i=pos%LED_COUNT;f[i*3+1]=64;send_frame(f);usleep(70000);}
        for(int phase=0;phase<90 && running;++phase){for(int i=0;i<LED_COUNT;++i){uint8_t r,g,b;hsv(fmodf(phase/90.0f+i/(float)LED_COUNT,1),0.20f,&r,&g,&b);f[i*3]=g;f[i*3+1]=r;f[i*3+2]=b;}send_frame(f);usleep(40000);}
        memset(f,0,sizeof(f)); send_frame(f);
    } else {
        fprintf(stderr, "Unknown command: %s\n", cmd); usage(argv[0]); rc=2;
    }

out:
    // Interrupting an animation always leaves the strip safely off.
    if ((!strcmp(cmd,"flash") || !strcmp(cmd,"chase") || !strcmp(cmd,"rainbow")) && pwm) {
        memset(f,0,sizeof(f)); send_frame(f);
    }
    pwm_clock_off();
    return rc;
}
