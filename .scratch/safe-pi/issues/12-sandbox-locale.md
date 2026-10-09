# 12 — The sandbox's locale does not exist in the image

**What to build:** The declared tools must run inside the sandbox under a UTF-8 locale, as they do on the host. The wrapper forwards the host's `LANG` (`en_US.UTF-8`), which `node:26-bookworm-slim` does not generate, so the Erlang VM starts with native name encoding latin1: every `elixir` invocation warns that it may malfunction, including the one mise runs while installing Elixir on the first converge.

**Status:** needs-info

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
