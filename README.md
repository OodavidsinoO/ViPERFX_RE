# ViPER4Android Reverse Engineered (ViPERFX_RE)

A reverse-engineered, modernized port of ViPER4Android. The DSP engine is
re-implemented from a decompilation of the original `libv4a_fx.so`, processing
audio in float32, with dead code removed and dependencies refreshed.

> **Not for commercial use.** This is a reverse-engineering project and may
> carry legal restrictions in your jurisdiction. Use at your own risk.

---

## Table of Contents

- [Overview](#overview)
- [Which module variant?](#which-module-variant)
- [Requirements](#requirements)
- [Installation](#installation)
- [Built-in sound effects removal](#built-in-sound-effects-removal)
- [Building from source](#building-from-source)
- [Module layout](#module-layout)
- [Diagnostics & troubleshooting](#diagnostics--troubleshooting)
- [FAQ](#faq)
- [Credits](#credits)

---

## Overview

This project ships as **two separate modules** built around the same DSP engine
(`ViPERDSP`), each integrated through a different Android audio interface.
They are **not interchangeable** — installing the wrong one does nothing (or
worse).

| Variant | Interface | Framework path | When to use |
|---|---|---|---|
| **Legacy (non-AIDL)** | classic `effect_handle_t` plugin (`libv4a_re.so`) | `audio_effects*.xml` configs merged by AudioFlinger | Devices with a HIDL audio HAL / legacy effect chain (all devices **launched before Android 15**) |
| **AIDL** | modern AIDL effect HAL (`libv4a_aidl.so`) | `audio_effects_config.xml` | Devices **launching with Android 15+**, whose audio HAL exposes an `*audio*aidl*` service |

How to check which one your device needs:

```bash
adb shell ps -A | grep "audio.*aidl"
```

Any audio HAL process with `aidl` in the name → AIDL module. Otherwise → Legacy
module.

> `ro.oplus.audio.effect.type` / Dolby / spatial audio: if your device still
> merges `audio_effects*.xml` (check `/vendor/etc/audio_effects*.xml` or
> `/odm/etc/audio_effects.xml`), you are on the **legacy** path — even on
> Android 14/15/16 updates of an older device.

---

## Requirements

- **Root**: Magisk, KernelSU, KernelSU-Next or APatch.
- **KernelSU/APatch**: a metamodule (`meta-overlayfs` / Hybrid Mount) is
  *optional* for this module — since v2.1.0 it self-mounts when nothing else
  did (see [Installation](#installation)).
- The audio output you use must go through AudioFlinger's software effect
  chain. Hardware-offloaded paths (Bluetooth A2DP offload, some USB DACs,
  tunneled DSP effects) bypass it by design.
- Tested hardware is narrow: non-AIDL on Pixel 8 Pro / Android 14, AIDL on
  Pixel 8 Pro / Android 16, plus OnePlus Open / OxygenOS 16 (legacy). Other
  devices may need vendor-specific shims or may simply do nothing. **Make a
  backup before flashing.**

---

## Installation

1. Install the **ViPER4Android app** (the driver companion):
   https://github.com/likelikeslike/ViPER4Android
2. Flash the module zip matching your device (see
   [Which module variant?](#which-module-variant)). **Do not flash both.**
3. Reboot.
4. Open the app, enable **Master power**, play audio, verify (see
   [Diagnostics](#diagnostics--troubleshooting)).

### KernelSU / APatch notes

- With a metamodule installed, the module files are mounted normally.
- **Without** a metamodule, KernelSU mounts nothing — `post-fs-data.sh` then
  bind-mounts the whole `soundfx` directories (the installer mirrors the stock
  soundfx libraries next to the driver) and every patched `audio_effects*`
  config into `/vendor`, `/odm` and `/system` itself, and restores the stock
  SELinux label on each bound file so `audioserver` can load it. Mounts are
  tracked in `.mounted` (used by uninstall) and logged under tag `v4a_re`.
  This is fully automatic; no extra packages needed.
- Safe mode (volume-down at boot) disables all modules, including this one.

### Upgrading

Remove the previous `ViPER4Android-RE` module first (same module ID), then
flash the new zip.

---

## Built-in sound effects removal

Since **v2.1.0**, the Legacy module strips built-in vendor sound effects from
the effect chain **generically** — by library name, library path keywords and
effect/apply names, with **no device or ROM hardcoding**:

- Dolby DAP / DAX: `dap`, `dvl`, `gamedap`, `libswdap_sp.so`,
  `libdlbvol_sp.so`, `libswgamedap_sp.so`, `dlb_*_listener` …
- OPPO/OnePlus: spatializer (`liboplus_spatializer.so`), upmix
  (`liboplusupmixeffect.so`), OZO surround (`libozoprocessing.so`)
- `service.sh` additionally stops native Dolby HAL services (any `init.svc.*`
  name containing `dolby`, e.g. `vendor.dolby_sp.hardware.dmssp@2.0`) and
  disables known Dolby packages (`com.dolby.daxservice`, …) when present.

Devices without such effects are untouched. This is what makes ViPER the only
effect in the chain on devices like the OnePlus Open (OxygenOS 16), where
Dolby is implemented natively **without any app to disable** in Settings.

### Things to know

- **Bluetooth**: A2DP hardware offload bypasses the software chain entirely.
  Enable *Developer options → Disable Bluetooth A2DP hardware offload* if you
  want ViPER on Bluetooth headsets (speaker / wired output is unaffected).
- **Spatial audio**: the OPPO/OnePlus spatializer effect is removed by the
  module; the Settings toggle, if still visible, will have no effect.

---

### One-click builds with GitHub Actions

`.github/workflows/build-module.yml` builds and packages the module on
demand — no local toolchain needed:

1. Go to **Actions → "Build ViPER module" → Run workflow**.
2. Optional inputs:
   - `version` — module version for the zip name; empty = read from
     `module/module.prop` (`v2.1.0`).
   - `use_latest_dsp` — pull the **latest upstream ViPERDSP** (`origin/main`)
     for this build only. The repository itself is never modified; the
     artifact gets a `-dsp-<sha>` suffix so the build stays traceable.
     Default off (builds are reproducible against the pinned submodule).
   - `create_release` — also create a **draft GitHub Release** with the zip
     (permanent download link). The release tag includes the `-dsp-<sha>`
     suffix when `use_latest_dsp` is on, so repeated runs never collide.
3. Download the zip from the run's **Artifacts** section (or the Release).

The workflow uses the runner's preinstalled Android NDK (27.3, same as the
Makefile default), checks out the `ViPERDSP` submodule recursively, and runs
the same `make zip` path as local builds.

## Building from source

### Prerequisites

- Android NDK (r27 or newer), e.g. `ANDROID_NDK_HOME=$HOME/ndk/android-ndk-r27c`
- CMake ≥ 3.16 and a generator: `make` or Ninja
- `zip`

### One-shot build (both ABIs + flashable zip)

```bash
git clone --recurse-submodules https://github.com/OodavidsinoO/ViPERFX_RE.git
cd ViPERFX_RE

export ANDROID_NDK_HOME=/path/to/android-ndk-r27c
make zip        # libs (arm64-v8a + armeabi-v7a) + ViPER4Android-RE-v2.1.0.zip
```

Output: `out/ViPER4Android-RE-v2.1.0.zip` — flash it in Magisk / KernelSU.

### With Ninja instead of make

```bash
for ABI in arm64-v8a armeabi-v7a; do
  cmake -G Ninja -B build/$ABI \
    -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=$ABI -DANDROID_PLATFORM=android-21 -DANDROID_ARM_NEON=TRUE \
    -DCMAKE_BUILD_TYPE=Release -DVERSION_CODE=20260808 -DVERSION_NAME=v2.1.0 .
  cmake --build build/$ABI
done
```

### Useful Makefile targets

| Target | What it does |
|---|---|
| `make libs` | build `libv4a_re.so` for both ABIs into `out/` |
| `make arm64-v8a` / `make armeabi-v7a` | single ABI |
| `make module` | assemble the flashable module directory |
| `make zip` | `module` + package `out/ViPER4Android-RE-<version>.zip` |
| `make clean` | remove `build/` and `out/` |

### The DSP submodule

The DSP engine lives in the `ViPERDSP` git submodule. It currently points at
upstream `e09f088` (`fix: Add missing includes`). To refresh:

```bash
git submodule update --init --recursive
git -C ViPERDSP fetch origin && git -C ViPERDSP checkout <new-head>
```

Bump it deliberately: the fork's `src/` is compiled against the submodule's
headers — re-run `make zip` and re-verify after any bump.

---

## Module layout

```
ViPERFX_RE/
├── src/                  # legacy driver: ViPER4Android.cpp, ViperContext.cpp
├── ViPERDSP/             # submodule: shared DSP engine (ViPER, convolver, …)
├── module/
│   ├── module.prop       # id=ViPER4Android-RE (do not change id once released)
│   ├── customize.sh      # MMT-Ex installer entry
│   ├── common/
│   │   ├── install.sh    # copies libs + patches every audio_effects*.xml/.conf
│   │   └── functions.sh  # MMT-Ex engine
│   ├── post-fs-data.sh   # KernelSU self-mount (soundfx dirs + configs, label restore)
│   ├── service.sh        # stops built-in Dolby audio HAL services (via init rc scan)
│   ├── sepolicy.rule     # audioserver access to the driver
│   └── uninstall.sh      # unmounts self-mounts, restores $INFO files
└── Makefile              # build + packaging
```

---

## Diagnostics & troubleshooting

Log tag for the driver: **`ViPER4Android`** (both variants). AIDL-only tags:
`AHAL_EffectImpl`, `AHAL_EffectContext`, `AHAL_EffectThread`. Boot-mount
diagnostics (KernelSU self-mount) log under **`v4a_re`**.

### Driver not found / not loaded

Run in order:

```bash
# 1. Is the driver file mounted with the right label?
adb shell su -c 'ls -Z /vendor/lib64/soundfx/libv4a_re.so'
#    expected: u:object_r:vendor_file:s0 ... libv4a_re.so

# 2. Is the config patched?
adb shell su -c 'grep -r v4a /odm/etc /vendor/etc /system/etc 2>/dev/null'

# 3. Is the effect registered in AudioFlinger?
adb shell su -c 'dumpsys media.audio_flinger | grep -E -B7 -A5 "90380da3"'
#    expected: an "Effect ID" block with UUID 90380da3-8536-4744-a6a3-5731970e640f

# 4. Any SELinux denials?
adb logcat -d | grep -E 'avc.*denied.*(v4a|soundfx)'
```

Missing at step 1 on KernelSU without a metamodule → check
`post-fs-data.sh` really ran (it must be executable in the zip and survive
install; re-flash if in doubt) and that bind mounts succeeded:

```bash
adb shell su -c 'mount | grep v4a_re'
```

Denials at step 4 → the SELinux label on the bound file was not restored; the
module's `sepolicy.rule` must be active (KernelSU loads it automatically).

### Effect registered but no processing

- Built-in effects still in the chain: `dumpsys media.audio_flinger | grep -i dolby`
  should be empty. If not, the config overlay did not apply — reflash and
  reboot, and make sure no other audio mod (e.g. AudioModificationLibrary)
  rewrote the configs after this module.
- Output is hardware-offloaded (A2DP offload, tunneled DSP): not fixable from
  the effect chain — see [Built-in sound effects removal](#built-in-sound-effects-removal).
- Try wired/speaker output first to validate the driver works at all.

### AIDL variant specifics

```bash
adb shell su -c 'grep v4a /vendor/etc/audio_effects_config.xml'
adb shell su -c 'ls -laZ /data/local/tmp/v4a/'        # SHM files, magic "V4MS"
```

---

## FAQ

**Does this work on OnePlus Open / OxygenOS 16?**
Yes — the Legacy module. The Open launched with Android 13, so it retains the
legacy `audio_effects.xml` chain (HIDL audio HAL, no `audio_effects_config.xml`).
Dolby there is native DAP (`libswdap_sp.so` + `dmssp` service, no app), which
the v2.1.0 module strips automatically.

**Can I keep the built-in effects and only add ViPER?**
Not with v2.1.0: the strip is intentional — ViPER must be the only effect to
behave predictably. Revert by using an older release or removing the module.

**Why is my Bluetooth audio untouched?**
A2DP hardware offload is enabled by default on most devices. Disable it in
Developer options.

**Does the AIDL module work with AudioModificationLibrary (AML)?**
No — confirmed incompatible. Disable AML when using the AIDL module.

---

## Credits

- Zhuhang and ViPER520 — original ViPER4Android
- Martmists, Iscle, llsl — reverse-engineering of the DSP
- Zackptg5 — MMT-Ex installer framework
- Desktop ports: [ViPER4Windows](https://github.com/likelikeslike/ViPER4Windows), [ViPER4Mac](https://github.com/likelikeslike/ViPER4Mac)
