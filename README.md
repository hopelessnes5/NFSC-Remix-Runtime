# NFSC Remix Runtime

An experimental NVIDIA RTX Remix runtime for **Need for Speed: Carbon**. The project adapts Carbon-specific compatibility work to a newer Remix runtime while building on the rendering and weather features developed for GTA IV Remix.

The goal is to make Carbon's original game geometry and materials usable by Remix's path tracer, while retaining support for existing Remix replacement assets. The runtime works together with a separate Carbon compatibility plugin that reads game data and supplies the render states needed by these features.

## Project background

The original point of reference for Carbon compatibility is XOXOR's [`game/nfsc_3` branch](https://github.com/xoxor4d/dxvk-remix/tree/game/nfsc_3). This project adapts that work to a newer runtime using ideas and implementations from XOXOR's [`game/gta4` branch](https://github.com/xoxor4d/dxvk-remix/tree/game/gta4), alongside components from [Remix Plus](https://github.com/RemixProjGroup/dxvk-remix) and NVIDIA's [RTX Remix Runtime](https://github.com/NVIDIAGameWorks/dxvk-remix).

This repository contains a snapshot of the adapted runtime sources. References to upstream branches describe the project's technical background; they do not imply that this repository preserves their complete Git history.

## Current work

- **Carbon compatibility:** runtime support for Carbon-specific per-draw material data supplied by the compatibility plugin.
- **Vehicle materials:** experimental paint, clear coat, wheel finishes and window tint. Metallic flakes are still an approximation and need further work.
- **Weather and wetness:** GTA IV-derived rain and surface wetness features adapted for Carbon. Puddles, rain exposure and their response to game conditions remain under development.
- **Material inspection:** the Remix developer UI can display and copy the geometry hash of a selected object, in addition to the texture hash. The displayed topological hash may differ from a mesh replacement hash.
- **Debug controls:** runtime controls for Carbon paint and tint are available in the Remix developer menu. Additional game-data inspection and overrides are provided by the separate compatibility plugin.

This is a **work in progress**, not a finished mod or a drop-in replacement for every Carbon Remix setup. Some features are experimental or require further in-game validation. Existing game configurations and replacement assets may need their own settings.

## Repository layout

| Path | Contents |
| --- | --- |
| `src/d3d9/` | D3D9 interception and game draw-call handling |
| `src/dxvk/` | Vulkan rendering, RTX Remix and fork-specific runtime systems |
| `src/dxvk/shaders/rtx/` | RTX shaders and shared shader definitions |
| `bridge/` | Bridge between the 32-bit game and the 64-bit runtime |
| `include/`, `submodules/` | Headers and third-party project sources |
| `docs/`, `documentation/` | Development and upstream documentation |
| `tests/` | Runtime and rendering tests |

The compatibility plugin, game files and Remix replacement assets are separate from this repository.

## Building

The runtime is built on Windows using **Meson** and the Visual Studio C++ toolchain. A working setup requires Visual Studio with C++ tools, the Windows SDK, a Vulkan SDK, Python, Meson, Ninja and the runtime's external dependencies, including the NVIDIA and third-party SDKs referenced by the Packman manifests.

For a configured development environment, generate and build the supported configurations from a PowerShell prompt in the repository root:

```powershell
.\build_dxvk_all_ninja.ps1
```

For an already configured build directory, build the runtime target with:

```powershell
meson compile -C _Comp64Release d3d9
```

See [`build_dxvk.ps1`](build_dxvk.ps1), [`build_common.ps1`](build_common.ps1), [`packman-external.xml`](packman-external.xml) and [`packman-dlnr.xml`](packman-dlnr.xml) for configuration and dependency details. The source snapshot contains third-party files copied from the development environment; it has not yet been verified as a clean, reproducible checkout on another machine. Generated build directories and some SDK links are not included in the snapshot.

## Testing and installation

The project requires a compatible copy of Need for Speed: Carbon, a matching Remix bridge and runtime build, and the separately built Carbon compatibility plugin. Remix assets and configuration are managed separately.

Before replacing an existing runtime, back up the game's current bridge/runtime files and configuration. Verify changes in game with the intended plugin and mod setup; a successful compile alone does not establish visual correctness or compatibility.

## Credits

- **XOXOR** — original Carbon Remix compatibility work and GTA IV Remix development.
- **NVIDIA and RTX Remix contributors** — RTX Remix runtime, SDK and tools.
- **Remix Plus contributors**, including Kim2091 — runtime extensions and rendering features used by this project.
- **DXVK contributors** — the D3D9-to-Vulkan foundation.
- Authors of the included libraries, tools and third-party components.

See [`LICENSE`](LICENSE), [`LICENSE-MIT`](LICENSE-MIT) and [`ThirdPartyLicenses.txt`](ThirdPartyLicenses.txt) for the applicable license and attribution information.
