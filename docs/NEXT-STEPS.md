# Next Steps — Your First 5-Minute Win

You have a working FM-1 toolchain, AC79 SDK, `linux/amd64` build container, and macOS CoreMIDI environment. Here is how to get your first win and pick a firmware direction.

## 1. Pick Your Starting Foundation

If you ran `./bin/fm1 setup` with no flags, [`felucca-bsp`](https://github.com/hugelton/felucca-bsp) is already cloned in `./workspace/felucca-bsp`. You can also switch or add any of the main community foundations:

| Command | Foundation | Best For |
|---|---|---|
| `./bin/fm1 setup` | [`felucca-bsp`](https://github.com/hugelton/felucca-bsp) *(default)* | Lean open-source hardware layer (display, keys, audio, MIDI, `.fwsc` loader) |
| `./bin/fm1 setup --starter fm1-base` | [`fm1-base`](https://github.com/charlesvestal/fm1-base) | Middleware on `felucca-bsp` with host simulator, web emulator, and `fm1_remote.py` |
| `./bin/fm1 setup --starter dinghy` | [`dinghy`](https://github.com/zvenson/dinghy) | Direct `felucca` / `sloop-fm1` lineage middleware |
| `./bin/fm1 setup --starter fm1-open` | [`fm1_open`](https://github.com/m-vave/fm1_open) | M-VAVE's official vendor open firmware |
| `./bin/fm1 setup --clone <git-url>` | Any community repo | Forking or modifying an existing open-source FM-1 synth/sequencer |

## 2. Your First 5-Minute Win

- **If you are using `felucca-bsp` (`./workspace/felucca-bsp`):**
  Explore `examples/` and open an interactive container shell with `JIELI_TOOLCHAIN` and `AC79_SDK` pre-wired:
  ```sh
  ./bin/fm1 shell --repo ./workspace/felucca-bsp
  ```
- **If you are using `fm1-base` (`./workspace/fm1-base`):**
  Run the host simulator/tests, build a `.fwsc`, and test a dry-run flash:
  ```sh
  ./bin/fm1 test --repo ./workspace/fm1-base --fuzz 2
  ./bin/fm1 build --repo ./workspace/fm1-base
  ./bin/fm1 flash --repo ./workspace/fm1-base --dry-run
  ```

## 3. Vibe-Coding Prompts for Your AI Agent

Point your coding agent at `AGENTS.md` in this kit plus your chosen `--repo`:

- *"Read `fm1-vibe-kit/AGENTS.md` and inspect `./workspace/felucca-bsp/examples/`. Build a minimal example that draws text on the FM-1 screen and plays a test tone on key press, then verify it compiles in `fm1 exec`."*
- *"Read `fm1-vibe-kit/AGENTS.md` and this `fm1-base` repo. Add a new synth preset or LED visualizer, run `fm1 test --fuzz 4` and `fm1 build`, and check SRAM headroom."*
- *"Check `fm1 crashes` over USB-MIDI against my latest build and help me diagnose the last crash."*

## 4. Where to Go for Inspiration

- [`w0ts/optimist`](https://github.com/w0ts/optimist) — modular FM-1 firmware & web editor exploring swappable synth/drum/sequencer blocks.
- [`isod89/sloop-fm1`](https://github.com/isod89/sloop-fm1) — community firmware in the direct `felucca` lineage.
