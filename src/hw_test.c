// SPDX-License-Identifier: GPL-3.0
// Copyright (C) 2025-2026 fanxiaobinggit
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define DEFAULT_INPUT "/dev/input/by-path/platform-gpio-keys-event"
#define DEFAULT_OUT1  "/sys/class/leds/dual_battery_b0/brightness"
#define DEFAULT_OUT2  "/sys/class/leds/dual_battery_c2/brightness"

static volatile sig_atomic_t running = 1;

struct options {
    const char *input;
    const char *out1;
    const char *out2;
    unsigned key_code;
    unsigned debounce_ms;
    bool toggle;
};

static void stop_handler(int signo) { (void)signo; running = 0; }

static void usage(const char *name)
{
    printf("Usage: %s [options]\n"
           "  --input PATH       input-event device (default: %s)\n"
           "  --key-code N       Linux input key code (default: 0x105 = BTN_5)\n"
           "  --out1 PATH        first LED brightness path (default: %s)\n"
           "  --out2 PATH        second LED brightness path (default: %s)\n"
           "  --toggle           toggle outputs on each press (default: latch high)\n"
           "  --debounce-ms N    press debounce time (default: 30)\n"
           "  -h, --help         show this help\n",
           name, DEFAULT_INPUT, DEFAULT_OUT1, DEFAULT_OUT2);
}

static unsigned parse_u32(const char *text, const char *what)
{
    char *end = NULL;
    unsigned long value = strtoul(text, &end, 0);
    if (!text[0] || !end || *end || value > UINT32_MAX) {
        fprintf(stderr, "Invalid %s: %s\n", what, text);
        exit(EXIT_FAILURE);
    }
    return (unsigned)value;
}

static int open_output(const char *path)
{
    int fd = open(path, O_WRONLY | O_CLOEXEC);
    if (fd < 0)
        fprintf(stderr, "Cannot open output %s: %s\n", path, strerror(errno));
    return fd;
}

static int set_output(int fd, int value)
{
    const char *text = value ? "1\n" : "0\n";
    if (lseek(fd, 0, SEEK_SET) < 0)
        return -1;
    return write(fd, text, 2) == 2 ? 0 : -1;
}

static uint64_t monotonic_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000u + (uint64_t)ts.tv_nsec / 1000000u;
}

int main(int argc, char **argv)
{
    struct options opt = {
        .input = DEFAULT_INPUT,
        .out1 = DEFAULT_OUT1,
        .out2 = DEFAULT_OUT2,
        .key_code = BTN_5,
        .debounce_ms = 30,
    };
    int input_fd = -1, out1_fd = -1, out2_fd = -1;
    bool outputs_high = false;
    uint64_t last_press_ms = 0;
    int result = EXIT_FAILURE;

    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--input") && i + 1 < argc) opt.input = argv[++i];
        else if (!strcmp(argv[i], "--key-code") && i + 1 < argc) opt.key_code = parse_u32(argv[++i], "key code");
        else if (!strcmp(argv[i], "--out1") && i + 1 < argc) opt.out1 = argv[++i];
        else if (!strcmp(argv[i], "--out2") && i + 1 < argc) opt.out2 = argv[++i];
        else if (!strcmp(argv[i], "--debounce-ms") && i + 1 < argc) opt.debounce_ms = parse_u32(argv[++i], "debounce time");
        else if (!strcmp(argv[i], "--toggle")) opt.toggle = true;
        else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) { usage(argv[0]); return 0; }
        else { usage(argv[0]); return EXIT_FAILURE; }
    }

    signal(SIGINT, stop_handler);
    signal(SIGTERM, stop_handler);

    input_fd = open(opt.input, O_RDONLY | O_CLOEXEC);
    if (input_fd < 0) {
        fprintf(stderr, "Cannot open input %s: %s\n", opt.input, strerror(errno));
        goto cleanup;
    }
    out1_fd = open_output(opt.out1);
    out2_fd = open_output(opt.out2);
    if (out1_fd < 0 || out2_fd < 0)
        goto cleanup;
    if (set_output(out1_fd, 0) < 0 || set_output(out2_fd, 0) < 0) {
        fprintf(stderr, "Initial output write failed: %s\n", strerror(errno));
        goto cleanup;
    }

    printf("Started: reading BTN_5 from %s; outputs low.\n", opt.input);
    fflush(stdout);
    result = EXIT_SUCCESS;

    while (running) {
        struct pollfd pfd = { .fd = input_fd, .events = POLLIN };
        struct input_event event;
        int ready = poll(&pfd, 1, 250);
        if (ready < 0) {
            if (errno == EINTR) continue;
            fprintf(stderr, "Input poll failed: %s\n", strerror(errno));
            result = EXIT_FAILURE;
            break;
        }
        if (ready == 0) continue;
        if (read(input_fd, &event, sizeof(event)) != sizeof(event)) {
            if (errno == EINTR) continue;
            fprintf(stderr, "Input event read failed: %s\n", strerror(errno));
            result = EXIT_FAILURE;
            break;
        }
        if (event.type != EV_KEY || event.code != opt.key_code || event.value != 1)
            continue;

        uint64_t now_ms = monotonic_ms();
        if (last_press_ms && now_ms - last_press_ms < opt.debounce_ms)
            continue;
        last_press_ms = now_ms;
        outputs_high = opt.toggle ? !outputs_high : true;
        if (set_output(out1_fd, outputs_high) < 0 || set_output(out2_fd, outputs_high) < 0) {
            fprintf(stderr, "Output write failed: %s\n", strerror(errno));
            result = EXIT_FAILURE;
            break;
        }
        printf("BTN_5 press -> outputs %s\n", outputs_high ? "HIGH" : "LOW");
        fflush(stdout);
    }

cleanup:
    if (out1_fd >= 0) set_output(out1_fd, 0);
    if (out2_fd >= 0) set_output(out2_fd, 0);
    if (out2_fd >= 0) close(out2_fd);
    if (out1_fd >= 0) close(out1_fd);
    if (input_fd >= 0) close(input_fd);
    return result;
}
