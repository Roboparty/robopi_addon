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
    const char *chip;
    unsigned sig_offset;
    unsigned led_offset;
    bool sig_active_low;
    bool led_active_low;
    unsigned debounce_ms;
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
           "  --chip PATH          GPIO chip (default: /dev/gpiochip3)\n"
           "  --sig N              SIG line offset (default: 9 = GPIO3_B1)\n"
           "  --led N              LED line offset (default: 14 = GPIO3_B6)\n"
           "  --sig-active-low     invert SIG logical level\n"
           "  --led-active-low     invert LED electrical level\n"
           "  --debounce-ms N      key debounce time (default: 30)\n"
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

static int request_input_events(int chip_fd, unsigned offset, bool active_low,
                                const char *label)
{
    struct gpioevent_request req;
    memset(&req, 0, sizeof(req));
    req.lineoffset = offset;
    req.handleflags = GPIOHANDLE_REQUEST_INPUT |
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

static int get_value(int fd)
{
    struct gpiohandle_data data;
    memset(&data, 0, sizeof(data));
    if (ioctl(fd, GPIOHANDLE_GET_LINE_VALUES_IOCTL, &data) < 0)
        return -1;
    return data.values[0] ? 1 : 0;
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
        .chip = "/dev/gpiochip3",
        .sig_offset = 9,   /* GPIO3_B1, button SIG, high when pressed */
        .led_offset = 14,  /* GPIO3_B6 */
        .debounce_ms = 30,
    };

    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--chip") && i + 1 < argc) opt.chip = argv[++i];
        else if (!strcmp(argv[i], "--sig") && i + 1 < argc) opt.sig_offset = parse_u32(argv[++i], "SIG offset");
        else if (!strcmp(argv[i], "--led") && i + 1 < argc) opt.led_offset = parse_u32(argv[++i], "LED offset");
        else if (!strcmp(argv[i], "--debounce-ms") && i + 1 < argc) opt.debounce_ms = parse_u32(argv[++i], "debounce time");
        else if (!strcmp(argv[i], "--on-press") && i + 1 < argc) opt.on_press = argv[++i];
        else if (!strcmp(argv[i], "--sig-active-low")) opt.sig_active_low = true;
        else if (!strcmp(argv[i], "--led-active-low")) opt.led_active_low = true;
        else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) { usage(argv[0]); return 0; }
        else { usage(argv[0]); return EXIT_FAILURE; }
    }

    signal(SIGINT, stop_handler);
    signal(SIGTERM, stop_handler);
    signal(SIGCHLD, SIG_IGN);

    int chip_fd = open(opt.chip, O_RDONLY | O_CLOEXEC);
    if (chip_fd < 0) {
        fprintf(stderr, "Cannot open %s: %s\n", opt.chip, strerror(errno));
        return EXIT_FAILURE;
    }

    int sig_fd = request_input_events(chip_fd, opt.sig_offset,
                                      opt.sig_active_low, "sig-led-sig");
    int led_fd = request_output(chip_fd, opt.led_offset,
                                opt.led_active_low, "sig-led-led");
    if (sig_fd < 0 || led_fd < 0) {
        if (led_fd >= 0) set_value(led_fd, 0);
        return EXIT_FAILURE;
    }

    int sig_level = get_value(sig_fd);
    if (sig_level < 0 || set_value(led_fd, sig_level) < 0) {
        fprintf(stderr, "Initial GPIO read/write failed: %s\n", strerror(errno));
        set_value(led_fd, 0);
        return EXIT_FAILURE;
    }
    printf("Started: SIG=%d, LED=%d. Button is active when SIG is high.\n",
           sig_level, sig_level);
    fflush(stdout);

    struct pollfd fd = {.fd = sig_fd, .events = POLLIN};
    uint64_t last_press_ms = 0;
    while (running) {
        int rc = poll(&fd, 1, 500);
        if (rc < 0) {
            if (errno == EINTR) continue;
            fprintf(stderr, "poll failed: %s\n", strerror(errno));
            break;
        }
        if (fd.revents & POLLIN) {
            struct gpioevent_data event;
            ssize_t count = read(sig_fd, &event, sizeof(event));
            if (count != (ssize_t)sizeof(event)) break;
            sig_level = get_value(sig_fd);
            if (sig_level < 0 || set_value(led_fd, sig_level) < 0) break;
            printf("SIG %s -> LED %s\n", sig_level ? "active" : "inactive",
                   sig_level ? "on" : "off");
            fflush(stdout);
            uint64_t now = monotonic_ms();
            if (sig_level == 1 &&
                (last_press_ms == 0 || now - last_press_ms >= opt.debounce_ms)) {
                last_press_ms = now;
                puts("KEY_PRESSED");
                fflush(stdout);
                run_press_command(opt.on_press);
            }
        }
    }

    set_value(led_fd, 0);
    close(led_fd);
    close(sig_fd);
    close(chip_fd);
    return 0;
}
