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
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;

struct options {
    const char *sig_chip;
    const char *led_chip;
    unsigned sig_offset;
    unsigned led_offset;
    bool sig_active_low;
    bool led_active_low;
    unsigned debounce_ms;
    unsigned led_on_ms;
    const char *on_press;
};

static void stop_handler(int signo)
{
    (void)signo;
    running = 0;
}

static void usage(const char *name)
{
    printf("Usage: %s [options]\n"
           "  --sig-chip PATH      SIG GPIO chip (default: /dev/gpiochip1)\n"
           "  --led-chip PATH      LED GPIO chip (default: /dev/gpiochip0)\n"
           "  --sig N              SIG offset (default: 29 = GPIO1_D5)\n"
           "  --led N              LED offset (default: 18 = GPIO0_C2)\n"
           "  --sig-active-low     invert SIG logical level\n"
           "  --led-active-low     invert LED electrical level\n"
           "  --debounce-ms N      rising-edge debounce time (default: 30)\n"
           "  --led-on-ms N        turn LED off after N ms (default: 0 = latch on)\n"
           "  --on-press COMMAND   run COMMAND for each valid key press\n"
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

static void run_press_command(const char *command)
{
    if (!command || !command[0])
        return;
    pid_t pid = fork();
    if (pid == 0) {
        execl("/bin/sh", "sh", "-c", command, (char *)NULL);
        _exit(127);
    }
    if (pid < 0)
        fprintf(stderr, "Cannot run key command: %s\n", strerror(errno));
}

int main(int argc, char **argv)
{
    struct options opt = {
        .sig_chip = "/dev/gpiochip1",
        .led_chip = "/dev/gpiochip0",
        .sig_offset = 29,  /* GPIO1_D5, button SIG, high when pressed */
        .led_offset = 18,  /* GPIO0_C2, LED, high when on */
        .debounce_ms = 30,
        .led_on_ms = 0,
    };

    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--sig-chip") && i + 1 < argc) opt.sig_chip = argv[++i];
        else if (!strcmp(argv[i], "--led-chip") && i + 1 < argc) opt.led_chip = argv[++i];
        else if (!strcmp(argv[i], "--sig") && i + 1 < argc) opt.sig_offset = parse_u32(argv[++i], "SIG offset");
        else if (!strcmp(argv[i], "--led") && i + 1 < argc) opt.led_offset = parse_u32(argv[++i], "LED offset");
        else if (!strcmp(argv[i], "--debounce-ms") && i + 1 < argc) opt.debounce_ms = parse_u32(argv[++i], "debounce time");
        else if (!strcmp(argv[i], "--led-on-ms") && i + 1 < argc) opt.led_on_ms = parse_u32(argv[++i], "LED on time");
        else if (!strcmp(argv[i], "--on-press") && i + 1 < argc) opt.on_press = argv[++i];
        else if (!strcmp(argv[i], "--sig-active-low")) opt.sig_active_low = true;
        else if (!strcmp(argv[i], "--led-active-low")) opt.led_active_low = true;
        else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) { usage(argv[0]); return 0; }
        else { usage(argv[0]); return EXIT_FAILURE; }
    }

    signal(SIGINT, stop_handler);
    signal(SIGTERM, stop_handler);
    signal(SIGCHLD, SIG_IGN);

    int sig_chip_fd = open(opt.sig_chip, O_RDONLY | O_CLOEXEC);
    if (sig_chip_fd < 0) {
        fprintf(stderr, "Cannot open %s: %s\n", opt.sig_chip, strerror(errno));
        return EXIT_FAILURE;
    }
    int led_chip_fd = open(opt.led_chip, O_RDONLY | O_CLOEXEC);
    if (led_chip_fd < 0) {
        fprintf(stderr, "Cannot open %s: %s\n", opt.led_chip, strerror(errno));
        close(sig_chip_fd);
        return EXIT_FAILURE;
    }

    int sig_fd = request_events(sig_chip_fd, opt.sig_offset,
                                opt.sig_active_low, "sig-led-sig");
    int led_fd = request_output(led_chip_fd, opt.led_offset,
                                opt.led_active_low, "sig-led-led");
    if (sig_fd < 0 || led_fd < 0) {
        if (led_fd >= 0) set_value(led_fd, 0);
        return EXIT_FAILURE;
    }

    if (set_value(led_fd, 0) < 0) {
        fprintf(stderr, "Initial LED write failed: %s\n", strerror(errno));
        set_value(led_fd, 0);
        return EXIT_FAILURE;
    }
    printf("Started: waiting for SIG rising edge; LED is off.\n");
    fflush(stdout);

    uint64_t last_rising_ms = 0;
    uint64_t led_off_at_ms = 0;
    while (running) {
        int timeout = -1;
        uint64_t now = monotonic_ms();
        if (led_off_at_ms) {
            timeout = now >= led_off_at_ms ? 0 : (int)(led_off_at_ms - now);
        }
        struct pollfd pfd = { .fd = sig_fd, .events = POLLIN };
        int ready = poll(&pfd, 1, timeout);
        if (ready < 0) {
            if (errno == EINTR) continue;
            fprintf(stderr, "SIG poll failed: %s\n", strerror(errno));
            break;
        }
        now = monotonic_ms();
        if (led_off_at_ms && now >= led_off_at_ms) {
            if (set_value(led_fd, 0) < 0) {
                fprintf(stderr, "LED write failed: %s\n", strerror(errno));
                break;
            }
            led_off_at_ms = 0;
            puts("LED off (timeout)");
            fflush(stdout);
        }
        if (ready == 0) continue;
        struct gpioevent_data event;
        if (read(sig_fd, &event, sizeof(event)) != sizeof(event)) {
            if (errno == EINTR) continue;
            fprintf(stderr, "SIG event read failed: %s\n", strerror(errno));
            break;
        }
        if (event.id != GPIOEVENT_EVENT_RISING_EDGE) continue;
        uint64_t event_ms = event.timestamp / 1000000u;
        if (last_rising_ms && event_ms - last_rising_ms < opt.debounce_ms)
            continue;
        last_rising_ms = event_ms;
        if (set_value(led_fd, 1) < 0) {
            fprintf(stderr, "LED write failed: %s\n", strerror(errno));
            break;
        }
        led_off_at_ms = opt.led_on_ms ? monotonic_ms() + opt.led_on_ms : 0;
        puts("SIG rising edge -> LED on");
        puts("KEY_PRESSED");
        fflush(stdout);
        run_press_command(opt.on_press);
    }

    set_value(led_fd, 0);
    close(led_fd);
    close(sig_fd);
    close(led_chip_fd);
    close(sig_chip_fd);
    return 0;
}
