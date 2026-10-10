# 19 — rtk cannot run in the arm64 sandbox: the image's glibc is too old

**What to build:** Move the sandbox image's base from `node:26-bookworm-slim`
(glibc 2.36) to `node:26-trixie-slim` (glibc 2.41), and bump the entrypoint
label so existing images are rebuilt. On a macOS host the sandbox runs
`linux/arm64`, and rtk publishes only a glibc-linked asset for that platform
(`rtk-aarch64-unknown-linux-gnu.tar.gz`), which needs `GLIBC_2.39`. Every Pi
start therefore warns:

    pi-rtk-optimizer: rtk binary unavailable, command rewrite bypassed
    (.../mise/installs/rtk/latest/rtk: /lib/aarch64-linux-gnu/libc.so.6:
    version `GLIBC_2.39' not found ...)

Ticket 14 verified rtk on x86_64 only, where mise picks the static
`x86_64-unknown-linux-musl` asset.

**Status:** claimed

- [ ] `safe-pi/Dockerfile` defaults `BASE_IMAGE` to `node:26-trixie-slim`, and
      the entrypoint label (Dockerfile and wrapper) is bumped so an existing
      bookworm image is rebuilt on the next start.
- [ ] On this macOS (arm64) host, a rebuilt sandbox runs `rtk --version`, and a
      Pi start no longer prints the `rtk binary unavailable` warning.
- [ ] The other declared tools still run in the rebuilt image, in particular the
      Ubuntu 22.04 precompiled Erlang/OTP (`erl`).
- [ ] ADR 0002's Erlang consequence names trixie instead of bookworm.
- [ ] `tests/run --full` prints `FULL GATE: PASS`.

## What is known

Found on 2026-10-11 on the macOS host:

- `safe-pi:current-u502` runs Debian 12.15, `ldd` 2.36.
- rtk v0.51.0 release assets: `aarch64-apple-darwin`,
  `aarch64-unknown-linux-gnu`, `x86_64-apple-darwin`,
  `x86_64-unknown-linux-musl`, Windows, rpm/deb. No arm64 musl build.
- The rtk binary already in `safe-pi-toolchain-u502`, run inside
  `node:26-trixie-slim` (glibc 2.41), prints `rtk 0.51.0`.

Rejected: building rtk from source (`cargo:rtk`) on arm64 only (a Rust
toolchain and a compile on every fresh volume), and pinning an older rtk whose
arm64 build needed less glibc (freezes a `latest` tool and breaks again on the
next bump).
