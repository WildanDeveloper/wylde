# Wylde init — PID 1

`src/init/init.c`, ~340 lines of C, statically linked. Replaces SysV init as
the real PID 1; SysV stays installed at `/sbin/sysvinit`, and the switch is one
kernel command line parameter, so reverting is editing one line in
`/etc/default/grub`.

## Principles

Nothing runs behind your back, including PID 1. The process list *is* a text
file:

```
# /etc/wylde/services
!sysctl     /sbin/sysctl --system
!modules    /sbin/modprobe -ab
sysklogd    /usr/sbin/syslogd -F
network     /sbin/dhcpcd -4 -b -q -t 10
tty1        /sbin/agetty --noclear tty1 9600 vt100
ttyS0       /sbin/agetty --noclear ttyS0 115200 vt100
```

- One line per service: `<name> <command>`. Anything not listed never starts.
- A leading `!` marks a one-shot service — it runs once and is not restarted
  (`sysctl`, `modprobe` finish and exit; restarting them would be a bug).
- Deleting a line disables a service. There is no registry, no symlink web, no
  hidden state.
- Every start, exit, signal death and respawn decision is printed to the
  console. If a process dies repeatedly (6 times), init stops restarting it and
  says so, rather than looping forever.

## What it does

1. Verifies it is PID 1. (`getpid() != 1` → refuse to run; two inits in one
   system is worse than none.)
2. Mounts `/dev` (devtmpfs), `/dev/pts`, `/proc`, `/sys`, `/run`, `/dev/shm` —
   so it does not depend on the LFS boot scripts existing or working.
3. Opens `/dev/console` for stdin/stdout/stderr.
4. Reads the service list, starts services in order.
5. Handles `SIGCHLD`: reaps, reports exit status or fatal signal, respawns
   (with a cap) unless the service is a one-shot or was stopped on purpose.
6. Handles `SIGTERM`/`SIGINT`: stops services in reverse order, escalates to
   `SIGKILL` after 5 seconds, syncs, then powers off or halts.
7. `SIGQUIT` prints a status table: name, state, pid, respawn count.

## Build

```bash
gcc -O2 -Wall -Wextra -static -o wylde-init src/init/init.c
```

Static, 766 KB, no library dependency at all — it runs before `ldconfig` has
ever been executed.

## Current limitations

Honest list, to be fixed in phase 2:

- No service dependencies or ordering groups beyond file order.
- No per-service restart rate limiting beyond the 6-strike cap.
- No `SIGUSR1`/`SIGUSR2` runtime control; changing the list needs a reboot
  (the file is read once, at start).
