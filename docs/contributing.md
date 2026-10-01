# Contributing to Wylde

## What this project is

Wylde is a Linux distribution built from nothing: no base distro, every package
compiled from upstream source. Three principles decide what goes in:

1. **Lean is a feature, not a trade-off.** Boot time and idle memory are release
   blockers. `tools/check-regression.py` fails the build when either grows.
2. **Complete defaults, user decides the rest.** The system ships what a
   developer or admin needs on day one. Everything else is one command away.
3. **Nothing runs behind your back.** Every service, every file, every byte is
   explainable. `wld info` can always answer "what is this and where did it
   come from".

## Ground rules for changes

- **No dependencies without a reason in the commit message.** A patch that adds
  a library dependency is a design decision, not a detail.
- **Every build error gets written down.** `docs/build-notes.md` is the project's
  memory: what broke, why, and what fixed it. It is more valuable than the code
  that avoided the bug next time.
- **Measurements, not adjectives.** "Slower" is not a review comment; "boot time
  went from 1.9 s to 2.3 s on the QEMU benchmark" is.
- **Lean is a feature.** If a change adds 600 MB of installed size, it needs a
  very good reason.

## Code

- `wld` — the package manager. Rust, statically linked against musl, **zero
  crates**. The whole program is in `wld/src/`. If you want to use a crate, that
  is a pull request worth discussing first.
- `wld/src/ports.rs` — fetch, unpack, build, stage, install. Read it before
  adding a step.
- `src/init/init.c` — PID 1. It starts only what `/etc/wylde/services` lists.
- `src/initramfs/probe.c` — finds the root filesystem before the real system
  exists. musl, static, no libraries.
- `src/doctor/` — `wylde-doctor`, reports and advises. Read-only by design.

### Style

- Rust: `cargo fmt` and `cargo clippy` clean. No `unsafe` without a comment
  explaining why it is sound.
- C: K&R braces, no hidden allocations in early boot code, every syscall error
  reported rather than ignored.
- Bash: `set -e`, quote every expansion, print what you are about to do.

## Tests

```bash
cd wld && cargo test          # the package manager's tests
cd src/doctor && cargo test   # the advisor's tests
```

Anything that touches `ports/` gets tested by building it:

```bash
wld build <name>              # stages without installing
wld install <name> && wld remove <name>
```

`wld remove` must leave the system exactly as it was. If files survive, the
recipe wrote outside `$PKG`.

## Submitting a port

1. Put the port in the right category (`core`, `apps`, `build`, `boot`).
2. Every source and patch checksummed.
3. `wld build <name>` and `wld install <name>` both succeed.
4. `wld remove <name>` removes every file it installed.
5. Say in the pull request what the package pulls in, and what it costs on disk.

## Sending a fix

Open an issue with the exact error text and what you expected. If the fix is
obvious, send the patch. When a fix is not obvious, add a paragraph to
`docs/build-notes.md` describing the trap you fell into — that paragraph will
save the next person an afternoon.
