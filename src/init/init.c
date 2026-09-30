#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <time.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define MAX_SERVICES 64
#define MAX_CMD 256
#define MAX_NAME 32

enum service_state { STOPPED, RUNNING, RESPAWNING, STOPPING };

struct service {
    char name[MAX_NAME];
    char cmd[MAX_CMD];
    pid_t pid;
    enum service_state state;
    unsigned int respawns;
    int oneshot;
};

static struct service services[MAX_SERVICES];
static int service_count;
static volatile sig_atomic_t child_event;
static volatile sig_atomic_t shutdown_request;
static int shutdown_signal;

static void log_line(const char *text)
{
    static const char tag[] = "[wylde-init] ";
    write(STDOUT_FILENO, tag, sizeof(tag) - 1);
    write(STDOUT_FILENO, text, strlen(text));
    write(STDOUT_FILENO, "\n", 1);
}

static void log_line2(const char *label, const char *value)
{
    static const char tag[] = "[wylde-init] ";
    write(STDOUT_FILENO, tag, sizeof(tag) - 1);
    write(STDOUT_FILENO, label, strlen(label));
    write(STDOUT_FILENO, value, strlen(value));
    write(STDOUT_FILENO, "\n", 1);
}

static void fatal(const char *what)
{
    static const char tag[] = "[wylde-init] fatal: ";
    write(STDOUT_FILENO, tag, sizeof(tag) - 1);
    write(STDOUT_FILENO, what, strlen(what));
    write(STDOUT_FILENO, "\n", 1);
    reboot(RB_POWER_OFF);
    _exit(1);
}

static int read_line(char *buf, size_t size)
{
    size_t used = 0;
    while (used + 1 < size) {
        char c;
        ssize_t n = read(STDIN_FILENO, &c, 1);
        if (n <= 0) {
            if (used == 0)
                return 0;
            break;
        }
        if (c == '\n')
            break;
        buf[used++] = c;
    }
    buf[used] = '\0';
    return 1;
}

static void load_services(const char *path)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        fatal("cannot read the service list");
        return;
    }
    dup2(fd, STDIN_FILENO);
    close(fd);

    char line[MAX_CMD];
    while (read_line(line, sizeof(line)) && service_count < MAX_SERVICES) {
        char *hash = strchr(line, '#');
        if (hash)
            *hash = '\0';
        char *text = line;
        while (*text == ' ' || *text == '\t')
            text++;
        size_t len = strlen(text);
        while (len > 0 && (text[len - 1] == '\n' || text[len - 1] == ' ' || text[len - 1] == '\r'))
            text[--len] = '\0';
        if (len == 0)
            continue;

        int oneshot = 0;
        if (*text == '!') {
            oneshot = 1;
            text++;
        }

        char *sep = strchr(text, ' ');
        if (!sep)
            continue;
        *sep = '\0';
        char *cmd = sep + 1;
        while (*cmd == ' ' || *cmd == '\t')
            cmd++;

        struct service *svc = &services[service_count++];
        snprintf(svc->name, sizeof(svc->name), "%s", text);
        snprintf(svc->cmd, sizeof(svc->cmd), "%s", cmd);
        svc->pid = 0;
        svc->state = STOPPED;
        svc->respawns = 0;
        svc->oneshot = oneshot;
    }
}

static int service_index(pid_t pid)
{
    for (int i = 0; i < service_count; i++) {
        if (services[i].pid == pid)
            return i;
    }
    return -1;
}

static void mount_one(const char *source, const char *target,
                      const char *fstype, unsigned long flags, const char *data)
{
    mkdir(target, 0755);
    if (mount(source, target, fstype, flags, data) != 0 && errno != EBUSY) {
        char message[128];
        snprintf(message, sizeof(message), "cannot mount %s (%s)", target, strerror(errno));
        log_line(message);
    }
}

static void ensure_filesystems(void)
{
    mount_one("devtmpfs", "/dev", "devtmpfs", MS_NOSUID, "mode=0755");
    mount_one("devpts", "/dev/pts", "devpts", MS_NOSUID | MS_NOEXEC, "gid=5,mode=0620");
    mount_one("proc", "/proc", "proc", MS_NOSUID | MS_NOEXEC | MS_NODEV, NULL);
    mount_one("sysfs", "/sys", "sysfs", MS_NOSUID | MS_NOEXEC | MS_NODEV, NULL);
    mount_one("tmpfs", "/run", "tmpfs", MS_NOSUID | MS_NODEV, "mode=0755");
    mount_one("tmpfs", "/dev/shm", "tmpfs", MS_NOSUID | MS_NODEV, "mode=1777");
}

static pid_t start_service(struct service *svc)
{
    fflush(stdout);
    pid_t pid = fork();
    if (pid < 0) {
        log_line("fork failed");
        return -1;
    }
    if (pid == 0) {
        setsid();
        signal(SIGCHLD, SIG_DFL);
        signal(SIGTERM, SIG_DFL);
        signal(SIGINT, SIG_DFL);
        signal(SIGQUIT, SIG_DFL);
        signal(SIGHUP, SIG_IGN);
        execl("/bin/sh", "sh", "-c", svc->cmd, (char *)NULL);
        _exit(127);
    }
    svc->pid = pid;
    svc->state = RUNNING;
    log_line2("starting ", svc->name);
    return pid;
}

static void stop_service(struct service *svc)
{
    if (svc->pid <= 0)
        return;
    svc->state = STOPPING;
    log_line2("stopping ", svc->name);
    kill(svc->pid, SIGTERM);
}

static void on_child(int sig)
{
    (void)sig;
    child_event = 1;
}

static void on_terminate(int sig)
{
    shutdown_request = 1;
    shutdown_signal = sig;
}

static void reap(int restart)
{
    while (1) {
        int status;
        pid_t pid = waitpid(-1, &status, WNOHANG);
        if (pid <= 0)
            break;
        int index = service_index(pid);
        if (index < 0)
            continue;
        struct service *svc = &services[index];
        svc->pid = 0;
        if (svc->state == STOPPING || shutdown_request) {
            svc->state = STOPPED;
            continue;
        }
        if (WIFSIGNALED(status)) {
            char message[128];
            snprintf(message, sizeof(message), "%s died on signal %d", svc->name, WTERMSIG(status));
            log_line(message);
        } else {
            char message[128];
            snprintf(message, sizeof(message), "%s exited with %d", svc->name, WEXITSTATUS(status));
            log_line(message);
        }
        if (restart && !svc->oneshot) {
            svc->respawns++;
            if (svc->respawns > 5) {
                char message[160];
                snprintf(message, sizeof(message),
                         "%s keeps dying (%u times) — not restarting it again", svc->name, svc->respawns);
                log_line(message);
                svc->state = STOPPED;
                continue;
            }
            svc->state = RESPAWNING;
            start_service(svc);
        } else {
            svc->state = STOPPED;
        }
    }
}

static void status(const char *reason)
{
    log_line2("status: ", reason);
    for (int i = 0; i < service_count; i++) {
        struct service *svc = &services[i];
        char state[16];
        switch (svc->state) {
        case RUNNING:
            snprintf(state, sizeof(state), "running");
            break;
        case STOPPING:
            snprintf(state, sizeof(state), "stopping");
            break;
        case RESPAWNING:
            snprintf(state, sizeof(state), "respawning");
            break;
        default:
            snprintf(state, sizeof(state), "stopped");
            break;
        }
        char line[160];
        snprintf(line, sizeof(line), "  %-20s %-12s pid=%ld respawns=%u%s",
                 svc->name, state, (long)svc->pid, svc->respawns,
                 svc->oneshot ? " (once)" : "");
        log_line(line);
    }
}

static void stop_everything(void)
{
    for (int i = service_count - 1; i >= 0; i--)
        stop_service(&services[i]);

    for (int waited = 0; waited < 50; waited++) {
        int remaining = 0;
        for (int i = 0; i < service_count; i++) {
            if (services[i].pid > 0)
                remaining++;
        }
        if (remaining == 0)
            return;
        struct timespec wait = {0, 100000000};
        nanosleep(&wait, NULL);
        reap(0);
    }

    for (int i = 0; i < service_count; i++) {
        if (services[i].pid > 0)
            kill(services[i].pid, SIGKILL);
    }
    reap(0);
}

int main(int argc, char **argv)
{
    const char *services_path = argc > 1 ? argv[1] : "/etc/wylde/services";
    int halt_poweroff = argc > 2 && strcmp(argv[2], "poweroff") == 0;

    if (getpid() != 1) {
        static const char notice[] = "[wylde-init] must run as PID 1\n";
        write(STDOUT_FILENO, notice, sizeof(notice) - 1);
        return 1;
    }

    log_line("starting");
    ensure_filesystems();

    pid_t console = open("/dev/console", O_RDWR);
    if (console >= 0) {
        dup2(console, STDIN_FILENO);
        dup2(console, STDOUT_FILENO);
        dup2(console, STDERR_FILENO);
        if (console > STDERR_FILENO)
            close(console);
    }

    load_services(services_path);
    log_line2("service list: ", services_path);

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_child;
    sigaction(SIGCHLD, &sa, NULL);
    sa.sa_handler = on_terminate;
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sa.sa_handler = SIG_IGN;
    sigaction(SIGHUP, &sa, NULL);

    signal(SIGPIPE, SIG_IGN);

    for (int i = 0; i < service_count; i++)
        start_service(&services[i]);

    while (!shutdown_request) {
        pause();
        if (child_event) {
            child_event = 0;
            reap(1);
        }
    }

    log_line2("shutting down on signal ", shutdown_signal == SIGINT ? "interrupt" : "term");
    stop_everything();
    status("shutdown complete");

    sync();
    log_line("halt");
    if (halt_poweroff)
        reboot(RB_POWER_OFF);
    reboot(RB_HALT_SYSTEM);
    for (;;)
        pause();
}
