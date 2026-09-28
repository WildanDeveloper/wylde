# Wylde Linux

> A Linux distribution built from scratch. No base distro. Terminal-first, desktop later.
> Philosophy: **"Complete, but lean."** — Everything you need ships by default, and not a single byte more.

| | |
|---|---|
| **Type** | Linux distribution built via LFS (Linux From Scratch) |
| **Base distro** | None. Everything compiled from upstream source |
| **Target user** | Developers, server admins, minimalists |
| **Init** | Custom init daemon, written in C |
| **Package manager** | `wld`, written in Rust |
| **Release 1.0** | CLI-only (terminal) |
| **Release 2.0** | Desktop (Wayland) |

## Core Principles

1. **Lean is a feature, not a trade-off.** Every release is measured: boot time and idle RAM. A release that regresses is rejected.
2. **Complete defaults, user decides the rest.** Daily-driver essentials ship in the ISO. Nothing else is preinstalled.
3. **Nothing runs behind your back.** Every service is visible, explainable, and one command away from being disabled.

## Status

Phase 0 — Preparation.
