# Wylde — Philosophy

**"Complete, but lean."**

Wylde exists because modern distributions optimize for the wrong thing. They optimize for what a machine *might* do someday, and ship megabytes of speculative software for it. Wylde optimizes for what a machine *actually does*: run a terminal, serve traffic, compile code.

## Lean is a feature, not a trade-off

Boot time and idle RAM are release blockers, not vanity metrics. Every release is measured in CI. A release that regresses against the previous one does not ship — regardless of what features it adds. Leanness is versioned, tested, and defended like any other API.

## Complete defaults, user decides the rest

The ISO ships what a developer or admin needs on day one: a shell, a compiler, networking, an editor, SSH. It does not ship what you might want someday. Extending the system is one command: `wld install <pkg>`. The defaults are an opinion, stated openly. Your machine, your call after that.

## Nothing runs behind your back

If a process is running, you can name it, explain it, and disable it in one command. No daemons that phone home. No services started "for convenience". The init system is ~500 lines of C — small enough that you can read all of it and know exactly what PID 1 is doing.

## Built, not based

Every package is compiled from upstream source via LFS. No base distro underneath, no inherited decisions, no unexplained binaries. The build is reproducible: the entire system can be rebuilt from `ports/` recipes on a clean directory with one command.

## The tool

The package manager `wld` is written in Rust, statically linked against musl: memory-safe, no runtime dependencies. Build recipes are plain Bash (`Pkgfile`) — readable, diffable, no DSL to learn.
