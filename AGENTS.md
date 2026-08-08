# Repository Guidelines

## Project Overview

ViPERFX_RE is a reverse-engineered, modernized port of ViPER4Android: the DSP
engine was re-implemented from a decompilation of the original `libv4a_fx.so`
(float32 processing, dead code removed). It ships as a Magisk/KernelSU module
that replaces the built-in (Dolby/OPPO/etc.) Android audio effects with ViPER.

- Repo is a fork of `likelikeslike/ViPERFX_RE`; working branch is `dev`.
- This repo builds only the **Legacy (non-AIDL)** variant (`libv4a_re.so`).
  The AIDL variant exists upstream but is not built here.
- Upstream DSP lives in the `ViPERDSP` git submodule (pinned at `e09f088`).

## Architecture & Data Flow

```
Android audioserver (AudioFlinger)
  └─ dlopens /vendor/lib64/soundfx/libv4a_re.so   (legacy effect plugin)
       └─ src/ViPER4Android.cpp   AOSP effect-library glue (AELI symbol,
                                  descriptor, create/release, callbacks)
            └─ src/ViperContext    effect state machine: SetConfig/SetParam/
                                   Process, PCM<->float32, fade-in, stream
                                   gap detection
                 └─ ViPERDSP/      static library, DSP facade
                      ViPER::DispatchRawParam / ViPER::Process / Apply*
```

- Audio is processed as **interleaved stereo float32** internally.
- Params flow: `effect_param_t` (legacy app protocol) → `ViperContext::HandleSetParam`
  → `ViPER::DispatchRawParam(param, v1, v2, v3, arr_size, arr)`.
- Driver UUID: `90380da3-8536-4744-a6a3-5731970e640f`; effect type:
  `ec7178ec-e5e1-4432-a3f4-4657e6795210`. Both are wired into every patched
  `audio_effects*.xml/.conf` as `<library name="v4a_re">` /
  `<effect name="v4a_standard_re">`.
- Module behavior at boot: `post-fs-data.sh` self-mounts on KernelSU without a
  metamodule (bind soundfx dirs + configs into `/vendor /odm /system`, restore
  stock SELinux labels, track mounts in `.mounted`); `service.sh` stops
  built-in Dolby HAL services; install-time `common/install.sh` strips
  Dolby/OPPO effects from all audio_effects configs and injects ViPER.

## Key Directories

| Path | Purpose |
|---|---|
| `src/` | Legacy driver: `ViPER4Android.cpp` (effect lib entry), `ViperContext.{h,cpp}` (state machine), `include/essential.h` (vendored AOSP `effect.h`) |
| `ViPERDSP/` | Git submodule (likelikeslike/ViPERDSP): DSP engine, `viper/ViPER.h` facade, `include/ViPERParams.h` (`viper::params::kParam*` ids), `include/log.h` (`VIPER_LOG*`, tag `ViPER4Android`) |
| `module/` | Flashable module: `module.prop`, `customize.sh` (MMT-Ex bootstrap), `common/functions.sh` (MMT-Ex engine), `common/install.sh` (lib copy + config patching), `post-fs-data.sh`, `service.sh`, `sepolicy.rule`, `uninstall.sh`, `META-INF/` |
| `.github/workflows/` | `build-module.yml` (manual CI), `close_issue.yml` (stale closer) |

## Development Commands

```bash
git submodule update --init --recursive   # ViPERDSP is REQUIRED for any build

export ANDROID_NDK_HOME=/path/to/android-ndk-r27c
make libs          # libv4a_re.so for arm64-v8a + armeabi-v7a -> out/
make arm64-v8a     # or: make armeabi-v7a
make module        # stage module tree -> out/magisk_module/
make zip           # module + package out/ViPER4Android-RE-<version>.zip
make clean
make format        # clang-format on src/
```

- No `make` on the host? Use cmake directly: `cmake -G Ninja -B build/<abi>
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake
  -DANDROID_ABI=<abi> -DANDROID_PLATFORM=android-21 -DANDROID_ARM_NEON=TRUE
  -DCMAKE_BUILD_TYPE=Release -DVERSION_CODE=<int> -DVERSION_NAME=<str> .` then
  `cmake --build build/<abi>`.
- Version: `make zip VERSION_NAME=vX.Y.Z VERSION_CODE=<int>`; defaults come
  from `module/module.prop` and are sed-injected at packaging time.
- CI (one-click): Actions → "Build ViPER module" → Run workflow. Inputs:
  `version` (empty = module.prop), `use_latest_dsp` (detach ViPERDSP to
  `origin/main` for this build only; artifact gets `-dsp-<sha>` suffix),
  `create_release` (draft GitHub Release).
- There is no test target and no linter gate.

## Code Conventions & Common Patterns

### C++ (src/)
- C++17; exceptions and RTTI disabled (`-fno-exceptions -fno-rtti`);
  `-fvisibility=hidden`; link with `-Wl,--gc-sections -Wl,--strip-all`.
- Formatting: LLVM-based clang-format, 4-space indent, 90 columns, attached
  braces, `kCamelCase` constants, snake_case functions/variables.
- `essential.h` is a **vendored copy of AOSP effect.h** — do not "improve" it.
- The DSP API surface (ViPERDSP submodule) is upstream-owned; bump the
  submodule deliberately and rebuild (see README). Upstream has no tags and
  no API stability guarantee.
- Known TODO: `src/ViperContext.cpp:593` "Remove fade-in".

### Shell (module/)
- POSIX sh only; must run under **Android toybox and busybox ash**: no
  process substitution, no `${var//}`, no arrays — use `while IFS= read -r`
  loops fed by pipes.
- Non-fatal best-effort pattern everywhere: `2>/dev/null`, `|| return 1`,
  `[ -f X ] || continue`. Never hard-fail a boot script.
- Log via `v4alog()` (`/system/bin/log -p i -t v4a_re` with echo fallback) —
  do NOT define a function named `log` (collides with `/system/bin/log`).
- Bind mounts require the **target to already exist** (ENOENT otherwise);
  that is why `install.sh` mirrors the stock soundfx libraries next to the
  driver and `post-fs-data.sh` binds whole directories, not per-file.
- MMT-Ex gotchas (don't fight the engine):
  - At install, the engine strips **all comment and blank lines** from every
    `.sh/.prop/.rule` and re-adds the shebang only for
    post-fs-data/service/uninstall. Don't rely on comments surviving.
  - `cp_ch` records backups in `$INFO` (`/data/adb/modules/.$MODID-files`);
    restore/removal happens on reinstall and in `uninstall.sh`.
  - `DYNLIB=true` → `LIBDIR=/system/vendor` for API ≥ 26; `LIBPATCH` is the
    sed-escaped path (`\/vendor`) used in `.conf` `path` lines.
  - Keep the "MMT Extended Logic" section of `customize.sh` and the arg
    contract of `cp_ch`/`install_script` (`getopt -o` + `eval set --`)
    untouched.
  - `update-binary` requires Magisk ≥ v20.4; `updater-script` is `#MAGISK`.

### Module identity & semantics
- `module/module.prop`: `id=ViPER4Android-RE` — **never change the id**:
  `uninstall.sh` fallback greps mounts for it, and users must remove an old
  module of the same id before flashing a new zip.
- `version` (vX.Y.Z) and `versionCode` (YYYYMMDD date code) must move in
  lockstep in `module.prop`, `Makefile` defaults, and the CI workflow.
- Generic effect stripping lives in `common/install.sh` as
  `DENY_LIB_NAMES` / `DENY_LIB_PATHS` / `DENY_EFFECTS` (dap/dvl/gamedap/
  spatializer/ozo/upmix + dolby/dax path keywords). Keep it generic — no
  device/ROM hardcoding.

## Important Files

| File | Why it matters |
|---|---|
| `src/ViPER4Android.cpp` | AELI entry point, effect descriptor, create/release, interface callbacks |
| `src/ViperContext.{h,cpp}` | Effect state machine, param marshalling, disable reasons |
| `ViPERDSP/viper/ViPER.h` | DSP facade: `Process`, `DispatchRawParam`, typed `Apply*`, convolver/DDC loaders |
| `module/common/install.sh` | Copies libs, mirrors stock soundfx, patches all `audio_effects*.xml/.conf` (strip + inject) |
| `module/post-fs-data.sh` | KernelSU self-mount; ODM configs bound **before** the early-exit (Magisk mounts system/vendor but not /odm) |
| `module/service.sh` | Stops built-in Dolby HAL services by scanning init rc for `vendor.dolby.*(dmssp|dms|dax)` (init service names ≠ binary paths, e.g. `dms-sp-hal-2-0`); leaves Dolby Vision (dvs/c2) alone |
| `module/sepolicy.rule` | audioserver read/exec/map on `vendor_file` + `odm_file` |
| `Makefile` / `CMakeLists.txt` | NDK build; `module.prop` version injection |
| `README.md` | Authoritative docs: variants, install, effect removal, diagnostics, FAQ |
| `module/LICENSE` | GPL-2.0 (the only license file; packaged into the zip) |

## Runtime/Tooling Preferences

- **Android audio stack**: this module targets the legacy `audio_effects*.xml`
  effect chain (HIDL audio HAL era, devices launched before Android 15).
  Devices with an AIDL audio HAL need the upstream AIDL variant, not this repo.
- **Root frameworks**: Magisk (magic mount) and KernelSU/APatch (self-mounting,
  no metamodule required since v2.1.0).
- **Build host**: Linux with NDK r27+ and CMake ≥ 3.16 (`make` or Ninja).
  GitHub Actions runner `ubuntu-24.04` has NDK 27.3 preinstalled
  (`ANDROID_NDK_HOME`); CI runs the same `make zip` path as local builds.
- **On-device shell**: toybox/busybox ash — write POSIX sh, test with
  `sh -n`, and prefer `sed`/`grep`/`find` pipelines over awk for
  portability-sensitive edits.
- Verification on device is manual: `dumpsys media.audio_flinger | grep
  90380da3`, `logcat -s ViPER4Android`, `logcat -s v4a_re`, `ls -Z
  /vendor/lib64/soundfx/libv4a_re.so` (see README "Diagnostics").

## Testing & QA

- **There are no automated tests in this repo.** Do not invent a test
  framework; the accepted verification flow is:
  1. `sh -n` on every touched shell script.
  2. Sandbox verification of config-processing logic against real firmware
     dumps (copy `audio_effects*.xml/.conf` into a fake root, run the sed
     pipeline, assert: v4a entries present exactly once, Dolby/OPPO entries
     gone, XML still well-formed, stock volume-listener entries kept).
  3. Build both ABIs, package the zip, verify its contents (libs valid ELF,
     19 files, version fields filled).
  4. On-device smoke test per README diagnostics (effect registered in
     AudioFlinger, Dolby gone from the chain, SELinux clean).
- Issue templates require device/ROM/module/app versions and diagnostic
  logs — always ask for `logcat` + `dumpsys media.audio_flinger` evidence
  when debugging effect-loading problems.
- Repo hygiene: commits follow Conventional Commits (`feat(module):`,
  `docs:`, `chore:`, `ci:`); `build/` and `out/` are gitignored; do not push
  without explicit user instruction.
