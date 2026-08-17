// SPDX-License-Identifier: GPL-3.0
// Copyright (C) 2025-2026 fanxiaobinggit
// RoboPi2 RK3588S PWM6_M1 (GPIO4_C1) WS2812 controller, 18 LEDs.
// Frames are transmitted by the roboparty_ws2812 kernel module.
// Build: gcc -O3 -Wall -Wextra -o ws2812_pwm6 ws2812_pwm6.c -lm
// Run:   sudo roboparty-ws2812 <off|on|solid|flash|chase|rainbow|demo> [args]
//
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define LED_COUNT       18
#define FRAME_BYTES     (LED_COUNT * 3)
#define DEVICE_PATH     "/dev/roboparty-ws2812"

static volatile sig_atomic_t running = 1;
static int device_fd = -1;

static void on_signal(int sig) { (void)sig; running = 0; }

static int open_backend(void) {
    device_fd = open(DEVICE_PATH, O_WRONLY | O_CLOEXEC);
    if (device_fd < 0) {
        perror("open " DEVICE_PATH);
        fprintf(stderr, "Kernel module is unavailable; try: sudo modprobe roboparty_ws2812\n");
        return -1;
    }
    return 0;
}

static int send_frame(const uint8_t frame[FRAME_BYTES]) {
    ssize_t n;
    do { n = write(device_fd, frame, FRAME_BYTES); } while (n < 0 && errno == EINTR);
    if (n != FRAME_BYTES) {
        if (n < 0) perror("write " DEVICE_PATH);
        else fprintf(stderr, "Short WS2812 frame write: %zd/%d bytes\n", n, FRAME_BYTES);
        return -1;
    }
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
    printf("  sudo %s timing                     repeat 0xAA for scope\n", p);
    printf("  sudo %s demo                       8-second test, then off\n", p);
}

int main(int argc, char **argv) {
    if (argc < 2 || !strcmp(argv[1], "help") || !strcmp(argv[1], "--help")) {
        usage(argv[0]); return argc < 2 ? 2 : 0;
    }
    if (geteuid() != 0) { fprintf(stderr, "Run with sudo.\n"); return 1; }
    signal(SIGINT, on_signal); signal(SIGTERM, on_signal);
    if (open_backend()) return 1;

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
    } else if (!strcmp(cmd, "timing")) {
        memset(f, 0xaa, sizeof(f));
        while (running) {
            if (send_frame(f)) { rc=1; break; }
            usleep(10000);
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
    if ((!strcmp(cmd,"flash") || !strcmp(cmd,"chase") || !strcmp(cmd,"rainbow") || !strcmp(cmd,"timing")) && device_fd >= 0) {
        memset(f,0,sizeof(f)); send_frame(f);
    }
    close(device_fd);
    return rc;
}
