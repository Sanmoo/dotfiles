# 12 — The sandbox's locale does not exist in the image

**What to build:** The declared tools must run inside the sandbox under a UTF-8 locale, as they do on the host. The wrapper forwards the host's `LANG` (`en_US.UTF-8`), which `node:26-bookworm-slim` does not generate, so the Erlang VM starts with native name encoding latin1: every `elixir` invocation warns that it may malfunction, including the one mise runs while installing Elixir on the first converge.

**Status:** ready-for-agent

- [ ] Inside `safe-pi --shell`, `elixir --version` prints no latin1 warning and `locale charmap` reports `UTF-8`.
- [ ] Pi and the other declared tools keep the host's locale behaviour rather than silently falling back to POSIX.

## What is known

- The host's `LANG` is `en_US.UTF-8`. The image ships no generated locale for it — only the glibc built-in `C.UTF-8` — because `node:26-bookworm-slim` carries no `locales` package and nothing runs `locale-gen`.
- Observed inside the sandbox (`safe-pi --shell`): `the VM is running with native name encoding of latin1 which may cause Elixir to malfunction as it expects utf8. Please ensure your locale is set to UTF-8 (which can be verified by running "locale" in your shell) or set the ELIXIR_ERL_OPTIONS="+fnu" environment variable`. Elixir works and reports `1.20.2`, but the VM's name encoding is the latin1 fallback.
- Found while implementing ticket 11 (`fde912f`), which made Elixir installable in the sandbox at all; this is not a regression it introduced.

## Open questions

- Generate the host's locale in the image (`locales` plus `locale-gen`), or pin the sandbox to the image's built-in `C.UTF-8` (rewriting or dropping the forwarded `LANG`/`LC_ALL`)?
- Which owns it: the image (`ENV` for `LANG`/`LC_ALL`, which the wrapper's `--env LANG` currently overrides), or the wrapper (forward the locale only when the image can honour it)?
- Is `ELIXIR_ERL_OPTIONS="+fnu"` — what the warning suggests — the right narrow fix, or a patch over the real locale question? It would silence Elixir without giving the rest of the toolchain the host's locale.

## Comments

### Decision (2026-10-09)

Measured inside `safe-pi:current-u1000` (`node:26-bookworm-slim`, glibc 2.36):

- The image carries no `/usr/share/i18n` and only glibc's built-in locale tree
  (`C.utf8`). `LC_ALL=C.UTF-8 locale charmap` answers `UTF-8`; the forwarded
  `LANG=en_US.UTF-8` makes glibc print `Cannot set LC_CTYPE to default locale`
  and answers `ANSI_X3.4-1968`.
- The Erlang VM follows that: `file:native_name_encoding()` returns `utf8`
  under `LC_ALL=C.UTF-8` and `latin1` under the forwarded `en_US.UTF-8` and
  under POSIX. The Elixir warning tracks the encoding, and
  `ELIXIR_ERL_OPTIONS=+fnu` does silence it under POSIX.
- `locales` costs 4.6 MB of archives / 20.7 MB installed, and
  `localedef -i en_US -f UTF-8 en_US.UTF-8` compiles that one locale into a
  2.9 MB `/usr/lib/locale/locale-archive`, after which `LANG=en_US.UTF-8 locale
  charmap` answers `UTF-8`. Debian's `locale-gen en_US.UTF-8` is a no-op unless
  `/etc/locale.gen` names the locale; `localedef` is the direct call and needs
  only `libc-bin`'s already-present binary.

Decisions:

- **Generate the host's locale; do not pin the sandbox to `C.UTF-8`.** The
  accepted criterion is the host's locale behaviour in Pi and the declared
  tools, and `C.UTF-8` is POSIX collation, time, and messages with a UTF-8
  charmap: the same `locale charmap` answer, a different `sort` order, `date`
  names, and message language. `en_US.UTF-8` is generated into the image, so
  the locale the wrapper forwards is honoured the way the host honours it.
- **The image ships the locales; the entrypoint enforces them.** The image
  installs `locales`, generates `en_US.UTF-8`, and defaults `LANG` to glibc's
  built-in `C.UTF-8` for a direct image run. The wrapper keeps forwarding
  `LANG`/`LC_ALL`/`LC_CTYPE` unchanged — forwarding host identity is its
  documented job — and the entrypoint replaces any of the three the image does
  not ship with `C.UTF-8` before convergence. The entrypoint owns it because
  the container can answer the availability question itself: no Docker query is
  added to the start path, and a direct image run gets the same guarantee.
- **`ELIXIR_ERL_OPTIONS=+fnu` is not the fix.** It silences Elixir alone,
  leaves every other tool on the POSIX charmap, and asks the VM for UTF-8
  filenames whatever the filesystem's locale is — the patch over the locale
  question, not an answer to it.
- **A host-driven `LOCALE` build argument is not the fix either.** Handing the
  host's locale to the build would make the image honour exactly one locale by
  construction, but the value lands in the layer chain before mise and Pi are
  installed, so every host locale change would rebuild the image's expensive
  layers. The entrypoint's availability check costs nothing at start.
