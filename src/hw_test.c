// SPDX-License-Identifier: GPL-3.0
// Copyright (C) 2025-2026 fanxiaobinggit
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/gpio.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;

struct options {
    const char *button_chip;
    const char *out1_chip;
    const char *out2_chip;
    unsigned button_offset;
    unsigned out1_offset;
    unsigned out2_offset;
    bool button_active_low;
    bool out1_active_low;
    bool out2_active_low;
    bool toggle;
    unsigned debounce_ms;
};

static void stop_handler(int signo)
{
    (void)signo;
    running = 0;
}

static void usage(const char *name)
{
    printf("Usage: %s [options]\n"
           "  --button-chip PATH   button GPIO chip (default: /dev/gpiochip1)\n"
           "  --button N           button offset (default: 29 = GPIO1_D5)\n"
           "  --out1-chip PATH     first output GPIO chip (default: /dev/gpiochip1)\n"
           "  --out1 N             first output offset (default: 8 = GPIO1_B0)\n"
           "  --out2-chip PATH     second output GPIO chip (default: /dev/gpiochip0)\n"
           "  --out2 N             second output offset (default: 18 = GPIO0_C2)\n"
           "  --button-active-low  invert button logical level\n"
           "  --out1-active-low    invert out1 electrical level\n"
           "  --out2-active-low    invert out2 electrical level\n"
           "  --toggle             toggle outputs on each press (default: latch high)\n"
           "  --debounce-ms N      rising-edge debounce time (default: 30)\n"
           "  -h, --help           show this help\n", name);
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

static int request_events(int chip_fd, unsigned offset, bool active_low,
                          const char *label)
{
    struct gpioevent_request req;
    memset(&req, 0, sizeof(req));
    req.lineoffset = offset;
    req.handleflags = GPIOHANDLE_REQUEST_INPUT |
                      GPIOHANDLE_REQUEST_BIAS_DISABLE |
                      (active_low ? GPIOHANDLE_REQUEST_ACTIVE_LOW : 0);
    req.eventflags = GPIOEVENT_REQUEST_BOTH_EDGES;
    snprintf(req.consumer_label, sizeof(req.consumer_label), "%s", label);
    if (ioctl(chip_fd, GPIO_GET_LINEEVENT_IOCTL, &req) < 0) {
        fprintf(stderr, "Cannot request %s (offset %u): %s\n",
                label, offset, strerror(errno));
        return -1;
    }
    return req.fd;
}

static int request_output(int chip_fd, unsigned offset, bool active_low,
                          const char *label)
{
    struct gpiohandle_request req;
    memset(&req, 0, sizeof(req));
    req.lineoffsets[0] = offset;
    req.lines = 1;
    req.flags = GPIOHANDLE_REQUEST_OUTPUT |
                (active_low ? GPIOHANDLE_REQUEST_ACTIVE_LOW : 0);
    req.default_values[0] = 0;
    snprintf(req.consumer_label, sizeof(req.consumer_label), "%s", label);
    if (ioctl(chip_fd, GPIO_GET_LINEHANDLE_IOCTL, &req) < 0) {
        fprintf(stderr, "Cannot request %s (offset %u): %s\n",
                label, offset, strerror(errno));
        return -1;
    }
    return req.fd;
}

static int set_value(int fd, int value)
{
    struct gpiohandle_data data;
    memset(&data, 0, sizeof(data));
    data.values[0] = value ? 1 : 0;
    return ioctl(fd, GPIOHANDLE_SET_LINE_VALUES_IOCTL, &data);
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
        .button_chip = "/dev/gpiochip1",
        .out1_chip = "/dev/gpiochip1",
        .out2_chip = "/dev/gpiochip0",
        .button_offset = 29,  /* GPIO1_D5, button, high when pressed */
        .out1_offset = 8,     /* GPIO1_B0, first output */
        .out2_offset = 18,    /* GPIO0_C2, second output */
        .debounce_ms = 30,
    };

    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--button-chip") && i + 1 < argc) opt.button_chip = argv[++i];
        else if (!strcmp(argv[i], "--button") && i + 1 < argc) opt.button_offset = parse_u32(argv[++i], "button offset");
        else if (!strcmp(argv[i], "--out1-chip") && i + 1 < argc) opt.out1_chip = argv[++i];
        else if (!strcmp(argv[i], "--out1") && i + 1 < argc) opt.out1_offset = parse_u32(argv[++i], "out1 offset");
        else if (!strcmp(argv[i], "--out2-chip") && i + 1 < argc) opt.out2_chip = argv[++i];
        else if (!strcmp(argv[i], "--out2") && i + 1 < argc) opt.out2_offset = parse_u32(argv[++i], "out2 offset");
        else if (!strcmp(argv[i], "--debounce-ms") && i + 1 < argc) opt.debounce_ms = parse_u32(argv[++i], "debounce time");
        else if (!strcmp(argv[i], "--button-active-low")) opt.button_active_low = true;
        else if (!strcmp(argv[i], "--out1-active-low")) opt.out1_active_low = true;
        else if (!strcmp(argv[i], "--out2-active-low")) opt.out2_active_low = true;
        else if (!strcmp(argv[i], "--toggle")) opt.toggle = true;
        else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) { usage(argv[0]); return 0; }
        else { usage(argv[0]); return EXIT_FAILURE; }
    }

    signal(SIGINT, stop_handler);
    signal(SIGTERM, stop_handler);

    int button_chip_fd = open(opt.button_chip, O_RDONLY | O_CLOEXEC);
    if (button_chip_fd < 0) {
        fprintf(stderr, "Cannot open %s: %s\n", opt.button_chip, strerror(errno));
        return EXIT_FAILURE;
    }
    int out1_chip_fd = open(opt.out1_chip, O_RDONLY | O_CLOEXEC);
    if (out1_chip_fd < 0) {
        fprintf(stderr, "Cannot open %s: %s\n", opt.out1_chip, strerror(errno));
        close(button_chip_fd);
        return EXIT_FAILURE;
    }
    int out2_chip_fd = open(opt.out2_chip, O_RDONLY | O_CLOEXEC);
    if (out2_chip_fd < 0) {
        fprintf(stderr, "Cannot open %s: %s\n", opt.out2_chip, strerror(errno));
        close(out1_chip_fd);
        close(button_chip_fd);
        return EXIT_FAILURE;
    }

    int button_fd = request_events(button_chip_fd, opt.button_offset,
                                   opt.button_active_low, "hw-test-button");
    int out1_fd = request_output(out1_chip_fd, opt.out1_offset,
                                 opt.out1_active_low, "hw-test-out1");
    int out2_fd = request_output(out2_chip_fd, opt.out2_offset,
                                 opt.out2_active_low, "hw-test-out2");
    if (button_fd < 0 || out1_fd < 0 || out2_fd < 0) {
        if (out1_fd >= 0) set_value(out1_fd, 0);
        if (out2_fd >= 0) set_value(out2_fd, 0);
        return EXIT_FAILURE;
    }

    if (set_value(out1_fd, 0) < 0 || set_value(out2_fd, 0) < 0) {
        fprintf(stderr, "Initial output write failed: %s\n", strerror(errno));
        return EXIT_FAILURE;
    }
    printf("Started: waiting for button (GPIO1_D5) rising edge; outputs low.\n");
    fflush(stdout);

    bool outputs_high = false;
    uint64_t last_rising_ms = 0;
    while (running) {
        struct pollfd pfd = { .fd = button_fd, .events = POLLIN };
        int ready = poll(&pfd, 1, -1);
        if (ready < 0) {
            if (errno == EINTR) continue;
            fprintf(stderr, "Button poll failed: %s\n", strerror(errno));
            break;
        }
        if (ready == 0) continue;

        struct gpioevent_data event;
        if (read(button_fd, &event, sizeof(event)) != sizeof(event)) {
            if (errno == EINTR) continue;
            fprintf(stderr, "Button event read failed: %s\n", strerror(errno));
            break;
        }
        if (event.id != GPIOEVENT_EVENT_RISING_EDGE) continue;

        uint64_t event_ms = event.timestamp / 1000000u;
        if (last_rising_ms && event_ms - last_rising_ms < opt.debounce_ms)
            continue;
        last_rising_ms = event_ms;

        outputs_high = opt.toggle ? !outputs_high : true;
        if (set_value(out1_fd, outputs_high) < 0 ||
            set_value(out2_fd, outputs_high) < 0) {
            fprintf(stderr, "Output write failed: %s\n", strerror(errno));
            break;
        }
        printf("Button press -> outputs %s\n", outputs_high ? "HIGH" : "LOW");
        fflush(stdout);
    }

    set_value(out1_fd, 0);
    set_value(out2_fd, 0);
    close(out2_fd);
    close(out1_fd);
    close(button_fd);
    close(out2_chip_fd);
    close(out1_chip_fd);
    close(button_chip_fd);
    return 0;
}
