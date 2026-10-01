/* probe — find the root filesystem before the real system is up.
 *
 * A tiny initramfs has no udev, no blkid, no libraries. This enumerates block
 * devices from sysfs, creates the device nodes it needs itself (devtmpfs is not
 * always around yet), reads each one's filesystem type straight out of its
 * superblock, and matches the requested root by device path or filesystem UUID.
 *
 * musl-gcc -static: no runtime dependencies, which is the whole point of code
 * that runs before the real libc exists.
 */

#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>

#define MAX_DEVICES 128
#define LINE 512

static void say(const char *text)
{
    static const char tag[] = "[wylde-initramfs] ";
    write(STDOUT_FILENO, tag, sizeof(tag) - 1);
    write(STDOUT_FILENO, text, strlen(text));
    write(STDOUT_FILENO, "\n", 1);
}

static void say2(const char *label, const char *value)
{
    static const char tag[] = "[wylde-initramfs] ";
    write(STDOUT_FILENO, tag, sizeof(tag) - 1);
    write(STDOUT_FILENO, label, strlen(label));
    write(STDOUT_FILENO, value, strlen(value));
    write(STDOUT_FILENO, "\n", 1);
}

static void die(const char *what)
{
    static const char tag[] = "[wylde-initramfs] fatal: ";
    write(STDOUT_FILENO, tag, sizeof(tag) - 1);
    write(STDOUT_FILENO, what, strlen(what));
    write(STDOUT_FILENO, "\n", 1);
    _exit(1);
}

static int read_first_line(const char *path, char *out, size_t size)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0)
        return 0;
    ssize_t n = read(fd, out, size - 1);
    close(fd);
    if (n <= 0)
        return 0;
    out[n] = '\0';
    char *newline = strchr(out, '\n');
    if (newline)
        *newline = '\0';
    return 1;
}

static int makedev_node(const char *path, unsigned int major, unsigned int minor)
{
    return mknod(path, S_IFBLK | 0600, makedev(major, minor));
}

/* /dev/<name> for a sysfs device, created if devtmpfs has not made it. */
static void ensure_node(const char *name, const char *devline)
{
    char path[128];
    snprintf(path, sizeof(path), "/dev/%s", name);
    if (access(path, F_OK) == 0)
        return;

    unsigned int major = 0, minor = 0;
    if (sscanf(devline, "%u:%u", &major, &minor) != 2)
        return;
    makedev_node(path, major, minor);
}

/* Filesystem type, read from the superblock: no libblkid needed. */
static ssize_t read_exact(int fd, char *buffer, size_t size)
{
    size_t done = 0;
    while (done < size) {
        ssize_t n = read(fd, buffer + done, size - done);
        if (n <= 0)
            break;
        done += (size_t)n;
    }
    return (ssize_t)done;
}

static const char *filesystem_of(const char *device)
{
    int fd = open(device, O_RDONLY);
    if (fd < 0)
        return NULL;
    char buffer[0x11000];
    ssize_t n = read_exact(fd, buffer, sizeof(buffer));
    close(fd);
    if (n < 2048)
        return NULL;

    /* ext2/3/4 magic 0xEF53 lives at offset 0x438, not 0x38 */
    if (buffer[0x438] == (char)0x53 && buffer[0x439] == (char)0xEF)
        return "ext4";
    if (memcmp(buffer, "XFSB", 4) == 0)
        return "xfs";
    if (n > 0x10048 && memcmp(buffer + 0x10040, "_BHRfS_M", 8) == 0)
        return "btrfs";
    if (buffer[0] == (char)0xf2 && buffer[1] == (char)0xf5)
        return "f2fs";
    return NULL;
}

static int ext_uuid_matches(const char *device, const char *wanted)
{
    int fd = open(device, O_RDONLY);
    if (fd < 0)
        return 0;
    char buffer[2048];
    ssize_t n = read_exact(fd, buffer, sizeof(buffer));
    close(fd);
    if (n < 2048)
        return 0;

    const unsigned char *raw = (const unsigned char *)buffer + 0x468;
    char uuid[64];
    snprintf(uuid, sizeof(uuid),
             "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
             raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
             raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]);
    return strcasecmp(uuid, wanted) == 0;
}

struct entry {
    char name[64];
    char devline[32];
};

/* Every block device and partition sysfs knows about, with its device node. */
static int collect_devices(struct entry *out, int max)
{
    int count = 0;
    DIR *block = opendir("/sys/block");
    if (block == NULL) {
        say("/sys/block is not readable: sysfs not mounted?");
        return 0;
    }

    struct dirent *disk_entry;
    while ((disk_entry = readdir(block)) != NULL && count < max) {
        if (disk_entry->d_name[0] == '.')
            continue;

        char disk_path[256];
        snprintf(disk_path, sizeof(disk_path), "/sys/block/%s", disk_entry->d_name);

        char devfile[320];
        char devline[LINE];
        snprintf(devfile, sizeof(devfile), "%s/dev", disk_path);
        if (read_first_line(devfile, devline, sizeof(devline)) && count < max) {
            ensure_node(disk_entry->d_name, devline);
            snprintf(out[count].name, sizeof(out[count].name), "%s", disk_entry->d_name);
            snprintf(out[count].devline, sizeof(out[count].devline), "%s", devline);
            count++;
        }

        DIR *parts = opendir(disk_path);
        if (parts == NULL)
            continue;
        struct dirent *part;
        while ((part = readdir(parts)) != NULL && count < max) {
            if (part->d_name[0] == '.')
                continue;
            char partfile[512];
            char partline[LINE];
            snprintf(partfile, sizeof(partfile), "%s/%s/dev", disk_path, part->d_name);
            if (!read_first_line(partfile, partline, sizeof(partline)))
                continue;
            ensure_node(part->d_name, partline);
            snprintf(out[count].name, sizeof(out[count].name), "%s", part->d_name);
            snprintf(out[count].devline, sizeof(out[count].devline), "%s", partline);
            count++;
        }
        closedir(parts);
    }
    closedir(block);
    return count;
}

static int try_mount(const char *name, const char *newroot)
{
    char device[128];
    snprintf(device, sizeof(device), "/dev/%s", name);
    const char *fs = filesystem_of(device);
    if (fs == NULL)
        return 0;
    mkdir(newroot, 0755);
    if (mount(device, newroot, fs, 0, NULL) != 0) {
        char line[160];
        snprintf(line, sizeof(line), "mount of %s failed: %s", device, strerror(errno));
        say(line);
        return 0;
    }
    say2("root is ", device);
    say2("filesystem ", fs);
    return 1;
}

/* The kernel registers disks asynchronously, so /sys/block can still be empty
 * right after boot. Wait like udevadm settle does. */
static int wait_for_devices(struct entry *out, int max, int attempts, int delay_us)
{
    int count = 0;
    for (int attempt = 0; attempt < attempts && count == 0; attempt++) {
        count = collect_devices(out, max);
        if (count == 0)
            usleep(delay_us);
    }
    return count;
}

int main(int argc, char **argv)
{
    const char *wanted = argc > 1 ? argv[1] : "";
    const char *root = "/newroot";

    say("probing for root");

    mkdir("/dev", 0755);
    mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
    mkdir("/proc", 0755);
    mount("proc", "/proc", "proc", 0, NULL);
    mkdir("/sys", 0755);
    mount("sysfs", "/sys", "sysfs", 0, NULL);
    mkdir("/run", 0755);
    mount("tmpfs", "/run", "tmpfs", 0, NULL);

    if (wanted[0] == '\0')
        die("no root= given");

    static struct entry devices[MAX_DEVICES];

    if (strncmp(wanted, "UUID=", 5) == 0) {
        const char *uuid = wanted + 5;
        int count = wait_for_devices(devices, MAX_DEVICES, 50, 200000);
        for (int i = 0; i < count; i++) {
            char device[128];
            snprintf(device, sizeof(device), "/dev/%s", devices[i].name);
            if (!ext_uuid_matches(device, uuid))
                continue;
            if (try_mount(devices[i].name, root))
                return 0;
        }
        die("no filesystem carries the requested UUID");
    }

    if (try_mount(wanted, root))
        return 0;

    /* LABEL= and PARTUUID= are not parsed: show what was found instead */
    say2("requested root looks like a label or PARTUUID: ", wanted);
    int count = wait_for_devices(devices, MAX_DEVICES, 50, 200000);
    for (int i = 0; i < count; i++) {
        char device[128];
        char line[128];
        snprintf(device, sizeof(device), "/dev/%s", devices[i].name);
        const char *fs = filesystem_of(device);
        snprintf(line, sizeof(line), "  %s %s", device, fs ? fs : "-");
        say(line);
    }
    die("root not found");
    return 1;
}
