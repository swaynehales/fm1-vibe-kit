# AGENTS.md — Using FM1-vibe-kit

This kit provides the `bin/fm1` CLI for developers and coding agents working on any M-VAVE FM-1 firmware repository.

## Standard Agent Loop

1. `bin/fm1 doctor --repo <fw-path>` — verify environment before touching code.
2. `bin/fm1 test --repo <fw-path> --fuzz 8` — run host tests + Linux ASan/UBSan fuzzing (when `tests/` is present).
3. `bin/fm1 build --repo <fw-path>` — build firmware via `./build.sh`, generate `.sym`, and inspect SRAM / `.pool` / `.ram_text` constraints (or `bin/fm1 exec --repo <fw-path> -- <cmd>` for custom build systems).
4. `bin/fm1 flash --repo <fw-path> --yes` and `bin/fm1 crashes --repo <fw-path>` — verify on physical FM-1 hardware over macOS CoreMIDI when `fm1_install.py` / `fm1_remote.py` are present.

## Firmware Rules of Thumb

- **Flash & SRAM are tight:** Check build size output after every change. Keep large zeroed buffers in `.pool` guarded with `#if defined(FM1_DEVICE) && defined(__ELF__)` (or your BSP's device macro) so macOS host builds compile cleanly.
- **Audio ISR vs. main loop:** Audio callbacks preempt the main loop; never mutate shared state in-place from UI/serialization paths while audio reads it, and avoid unbounded single-precision float time accumulators.
- **Host vs. device checks:** Host tests catch DSP/migration logic, not `.ram_text` no-call/single-precision-FPU rules or flash/SRAM overflow. Always run a target firmware build before claiming a firmware change is ready.
