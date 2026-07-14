# Synaptics pointer inertia

This fork adds optional inertial pointer movement to
`xf86-input-synaptics`. It does not change the original driver behavior until
pointer inertia is explicitly enabled.

## Attribution

The pointer inertia extension was implemented by OpenAI Codex at the request
of Rumen V. Simeonov. Rumen specified the required interaction behavior and
performed practical testing and tuning on Dell touchpad hardware and an
HP EliteBook 830 G6.

The underlying Synaptics driver is an X.Org project with many original
contributors. It remains covered by the MIT license in `COPYING`.

## Requirements

- An X.Org session. This driver is not used by native Wayland sessions.
- X.Org server development headers.
- libevdev, XInput, XTest, Autoconf, Automake, Libtool, and X.Org macros.

For Debian-based systems:

```sh
sudo apt-get install build-essential autoconf automake libtool pkgconf \
  xutils-dev xserver-xorg-dev libevdev-dev libxi-dev libxtst-dev \
  xserver-xorg-input-synaptics
```

## Guided installation

On Debian or MX Linux, the installation script handles the dependencies,
build, backup, module installation, and X.Org configuration:

```sh
git clone https://github.com/rumenvsimeonov-afk/xf86-input-synaptics-pointer-inertia.git
cd xf86-input-synaptics-pointer-inertia
./install-pointer-inertia.sh
sudo reboot
```

Useful modes:

```sh
./install-pointer-inertia.sh --build-only
./install-pointer-inertia.sh --no-deps
./install-pointer-inertia.sh --uninstall
```

The script never restarts the graphical session automatically. It preserves
the first driver module that it replaces in:

```text
/var/lib/xf86-input-synaptics-pointer-inertia/
```

## Build

```sh
NOCONFIGURE=1 ./autogen.sh
mkdir -p build
cd build
../configure \
  --prefix=/usr \
  --with-xorg-module-dir=/usr/lib/xorg/modules \
  --with-xorg-conf-dir=/usr/share/X11/xorg.conf.d
make -j"$(nproc)"
```

Before installing a development build, back up the packaged module:

```sh
sudo cp -a /usr/lib/xorg/modules/input/synaptics_drv.so \
  /usr/lib/xorg/modules/input/synaptics_drv.so.packaged
sudo install -m 0644 src/.libs/synaptics_drv.so \
  /usr/lib/xorg/modules/input/synaptics_drv.so
```

Restart the X.Org session or reboot. Confirm the active driver with:

```sh
grep -A6 "Module synaptics" /var/log/Xorg.0.log
```

## XInput properties

Use the touchpad name reported by:

```sh
xinput list --name-only
```

The property IDs are allocated dynamically by X.Org and may change after a
restart. Use the stable property names instead.

### Synaptics Pointer Inertia

One boolean value:

1. `enabled`: `0` preserves the original driver behavior; `1` enables pointer
   inertia.

```sh
xinput set-prop "TOUCHPAD NAME" "Synaptics Pointer Inertia" 1
```

### Synaptics Pointer Inertia Motion

Six floating-point values:

1. `min_velocity`: minimum release velocity in mm/s.
2. `start_multiplier`: multiplier applied to release velocity.
3. `decay_time`: exponential decay time constant in milliseconds.
4. `stop_velocity`: velocity in mm/s below which inertia stops.
5. `min_distance`: minimum finger travel in mm.
6. `lift_tail_ratio`: sensitivity for trimming slowdown while lifting.

Defaults:

```text
3.1  0.88  1658  1.9  0.75  0.45
```

Example with easier inertia startup:

```sh
xinput set-prop "TOUCHPAD NAME" \
  "Synaptics Pointer Inertia Motion" \
  2.5 0.88 1658 1.9 0.5 0.45
```

### Synaptics Pointer Inertia Timing

Five integer values in milliseconds:

1. `min_touch_time`: minimum duration of the qualifying touch.
2. `velocity_stale_time`: maximum age of samples used for release velocity.
3. `stop_touch_time`: touch duration required to stop active inertia.
4. `retouch_arm_time`: delay after release before a retouch may stop inertia.
5. `max_duration`: safety limit for inertia; `0` disables the limit.

Defaults:

```text
50  150  24  200  0
```

Example with a longer minimum touch:

```sh
xinput set-prop "TOUCHPAD NAME" \
  "Synaptics Pointer Inertia Timing" \
  80 150 24 200 0
```

### Synaptics Pointer Inertia Sampling

Two integer values:

1. `velocity_samples`: number of recent samples used for release velocity.
2. `tail_samples`: number of final samples checked for lift slowdown.

Defaults:

```text
8  10
```

The sum cannot exceed the internal 100-sample history.

### Synaptics Pointer Inertia Behavior

Two boolean values:

1. `restart_after_stop`: after a confirmed touch stops active inertia, the
   same still-down finger can continue normal pointer movement and may start
   new inertia on release.
2. `edge_scroll_exit`: a touch that begins in an edge-scroll zone may start
   pointer inertia only if it leaves all edge-scroll zones before release.
   Releasing inside a scroll zone remains normal Synaptics scrolling.

Defaults:

```text
1  1
```

Example disabling the edge-scroll handoff:

```sh
xinput set-prop "TOUCHPAD NAME" \
  "Synaptics Pointer Inertia Behavior" \
  1 0
```

### Synaptics Pointer Inertia ClickGen TapTime

One integer value in milliseconds:

1. `clickgen_tap_time`: maximum duration of a stop touch that may generate
   the configured one-finger tap button after stopping active pointer inertia.

Defaults:

```text
128
```

Set this value to `0` to disable stop-touch click generation. Values below
5 ms are also treated as disabled. A generated click is allowed only for a
short, clean one-finger stop touch: movement beyond `Synaptics Tap Move`,
physical buttons, multitouch, or `TouchpadOff` tap suppression prevent it.
Longer stop touches only stop pointer inertia.

```sh
xinput set-prop "TOUCHPAD NAME" \
  "Synaptics Pointer Inertia ClickGen TapTime" 0
```

### Synaptics Pointer Inertia Drag Lock

Three integer values:

1. `enabled`: `1` enables the custom pointer-inertia-aware locked drag.
2. `timeout_ms`: maximum locked-drag duration in milliseconds; `0` disables
   automatic release.
3. `cancel_touch`: when enabled, right button, middle button, or two-finger
   touch cancels the custom locked drag.

Defaults:

```text
0  0  1
```

When this feature is enabled, the driver disables the original
`Synaptics Locked Drags` implementation internally. The custom implementation
keeps the virtual drag button held while pointer inertia is active, allows
drag inertia on the first release after locked drag starts, and allows a
continued touch to stop inertia and resume normal locked dragging.

```sh
xinput set-prop "TOUCHPAD NAME" \
  "Synaptics Locked Drags" 0
xinput set-prop "TOUCHPAD NAME" \
  "Synaptics Pointer Inertia Drag Lock" 1 0 1
```

### Synaptics Pointer Inertia Drag Lock Cancel

One 8-bit boolean control property. Setting it to `1` asks the driver to
cancel an active custom locked drag. It is intended for helper programs rather
than normal manual tuning.

```sh
xinput set-prop "TOUCHPAD NAME" \
  "Synaptics Pointer Inertia Drag Lock Cancel" 1
```

The included `pointer-inertia-esc-cancel` helper listens for raw Escape key
presses through XInput2 and toggles this property without stealing Escape from
applications:

```sh
pointer-inertia-esc-cancel &
```

Use `-n "TOUCHPAD NAME"` to bind it to a specific device, or `-v` for a small
diagnostic log.

### Synaptics Pointer Inertia Debug

One boolean value. When enabled, start, rejection, trimming, retouch, click
generation, and stop decisions are written to the X.Org log. Gesture/click
rejections include diagnostic reason flags.

```sh
xinput set-prop "TOUCHPAD NAME" \
  "Synaptics Pointer Inertia Debug" 1
```

## X.Org configuration

Runtime properties reset when the X.Org session restarts. To enable the
feature permanently, add options to the touchpad `InputClass`:

```text
Section "InputClass"
    Identifier "Synaptics pointer inertia"
    MatchIsTouchpad "on"
    MatchDriver "synaptics"
    Option "PointerInertia" "on"
    Option "PointerInertiaMinVelocity" "3.1"
    Option "PointerInertiaStartMultiplier" "0.88"
    Option "PointerInertiaDecayTime" "1658"
    Option "PointerInertiaStopVelocity" "1.9"
    Option "PointerInertiaMinDistance" "0.75"
    Option "PointerInertiaLiftTailRatio" "0.45"
    Option "PointerInertiaMinTouchTime" "50"
    Option "PointerInertiaVelocityStaleTime" "150"
    Option "PointerInertiaStopTouchTime" "24"
    Option "PointerInertiaRetouchArmTime" "200"
    Option "PointerInertiaMaxDuration" "0"
    Option "PointerInertiaVelocitySamples" "8"
    Option "PointerInertiaTailSamples" "10"
    Option "PointerInertiaRestartAfterStop" "on"
    Option "PointerInertiaEdgeScrollExit" "on"
    Option "PointerInertiaClickGenTapTime" "128"
    Option "PointerInertiaDragLock" "off"
    Option "PointerInertiaDragLockTimeout" "0"
    Option "PointerInertiaDragLockCancel" "on"
    Option "PointerInertiaDebug" "off"
EndSection
```

The guided installer preserves an existing
`/etc/X11/xorg.conf.d/99-synaptics-pointer-inertia.conf` instead of
overwriting local tuning. When upgrading from an older release, update that
file manually or use the runtime `~/.xsessionrc` example below.

## Runtime X Session Tuning

If you prefer runtime tuning with `xinput`, add commands to `~/.xsessionrc`.
This is useful while experimenting because values can be changed without
reinstalling the driver. A compact example is provided in:

```text
examples/xsessionrc-pointer-inertia
```

Replace `TOUCHPAD NAME` in that file with the exact device name reported by
`xinput list --name-only`.

## Safety behavior

The following rules are intentional and are not optional tuning controls:

- A click, drag, scroll operation, or multitouch gesture disqualifies the
  current touch from starting pointer inertia.
- A retouch used to stop inertia is excluded from normal tap and click
  processing.
- A short likely-false retouch is ignored.
- A short clean stop touch may optionally generate the configured one-finger
  tap button; set `PointerInertiaClickGenTapTime` to `0` to disable this.
- After a confirmed stop, the same finger can continue normal pointer motion
  and may start fresh inertia on release.
- A movement that begins in an edge-scroll zone is treated as scrolling unless
  it leaves the scroll zone before release.
- When custom drag lock is enabled, the original Synaptics locked-drags
  feature is disabled to avoid two independent drag state machines.
- Custom drag lock cancellation moves the pointer to screen coordinate `0,0`
  before releasing the virtual button. This avoids accepting a drop at the
  current pointer location in file managers and editors tested so far.
- Motion blocked by a screen edge is stopped through visible-pointer
  feedback.

## Rollback

Restore the packaged module and restart X.Org:

```sh
sudo install -m 0644 \
  /usr/lib/xorg/modules/input/synaptics_drv.so.packaged \
  /usr/lib/xorg/modules/input/synaptics_drv.so
```

Alternatively, reinstall the distribution package:

```sh
sudo apt-get --reinstall install xserver-xorg-input-synaptics
```
