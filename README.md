# dispctl

[![CI](https://github.com/Forger7/dispctl/actions/workflows/ci.yml/badge.svg)](https://github.com/Forger7/dispctl/actions/workflows/ci.yml)

Connect and disconnect macOS displays from the terminal.

Disconnecting makes macOS treat a display as unplugged: windows evacuate, the desktop
arrangement drops it, and nothing new is ever placed there — while the cable stays
physically connected.

The use case this was built for: a monitor with two inputs, a Mac on one and another device
on the other. Switching the monitor's input isn't enough, because the Mac still sees the
panel over its own cable and cheerfully keeps putting windows on a screen you can't see.

```
$ dispctl list
ID    STATUS  UUID                                  NAME
1     on      22F82439-11C4-4108-9A65-EFEFDCD9C74B  ARZOPA
2     on      C16D249C-4CE9-4AEE-99DA-AE99D9E770D9  ED323QUR A (1)
3     on      F288252F-3658-4B0F-AB27-B26C511FE8FB  ED323QUR A (2)

$ dispctl off F288252F
ED323QUR A (2) [F288252F] → disconnected
```

Run `dispctl` with no arguments for an interactive picker: arrow keys or `j`/`k` to move,
space to toggle, `r` to refresh, `q` to quit.

## Install

Requires macOS 13 (Ventura) or later on Apple Silicon.

```sh
brew install Forger7/tap/dispctl
```

That pours a prebuilt binary, so no Swift toolchain is needed. If no bottle matches your
machine, Homebrew builds from source instead, and that fallback does need one
(`xcode-select --install`).

Or from source:

```sh
git clone https://github.com/Forger7/dispctl
cd dispctl
swift build -c release
cp .build/release/dispctl ~/.local/bin/   # or anywhere on your PATH
```

## Usage

```
dispctl                        interactive picker
dispctl list [--json]          list displays
dispctl off <display>          disconnect
dispctl on <display>           reconnect
dispctl toggle <display>       flip whichever way it is now

--session    revert at logout instead of persisting the change
```

`<display>` is a UUID prefix, a numeric id, or part of the display name. **Prefer UUIDs** —
numeric ids get reassigned across reboots and replugs, and a name substring can match more
than one identical monitor.

`on` and `off` are idempotent, so they are safe to bind to a key or call from a script.

### If a display disappears

Once disabled, macOS may stop reporting the display altogether. `dispctl` remembers what it
turned off in `~/.local/state/dispctl/disabled.json` and still lists it, marked `off*`:

```
3     off*    F288252F-3658-4B0F-AB27-B26C511FE8FB  ED323QUR A (2)
```

If that state is ever lost, `dispctl on <numeric id>` will attempt a reconnect against a raw
display id that isn't currently listed. Failing that, unplugging and replugging the cable, or
logging out, always restores everything.

## How it works

macOS ships a private function that brings a display in and out of the desktop layout:
`SLSConfigureDisplayEnabled` in SkyLight.framework, re-exported by CoreGraphics as
`CGSConfigureDisplayEnabled`. It's what WindowServer uses internally. `dispctl` resolves it at
runtime with `dlopen`/`dlsym` and wraps the call in the normal
`CGBeginDisplayConfiguration` / `CGCompleteDisplayConfiguration` transaction.

**This is a private API.** It's undocumented, absent from the public SDK, and Apple owes you
no stability. If a future macOS moves it, `dispctl` fails loudly rather than misbehaving
quietly, and you can find where it went with:

```sh
dyld_info -exports /System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight \
  | grep -i DisplayEnabled
```

## Alternatives

`dispctl` is deliberately small: one job, no menu bar, no daemon, scriptable.

- **[Crisp](https://github.com/didriksg/Crisp)** — free, open source, actively maintained menu
  bar app that does this and much more (HiDPI scaling, DDC brightness, presets, virtual
  displays). **If you want a GUI, use Crisp instead of this.** Its `crispctl` CLI currently
  covers only `displays list` and brightness, which is why `dispctl` exists.
- **[MacDisplayTool](https://github.com/laosb/MacDisplayTool)** — the closest prior art; same
  API, same idea, list and enable/disable. Unmaintained since mid-2025 and lists only active
  displays, so it can't easily reconnect one that has vanished.
- **[LightsOut](https://github.com/AlonX2/LightsOut)** — menu bar app for disabling monitors.
- **BetterDisplay / Lunar** — excellent, far deeper, and both put display disconnect behind a
  paid tier.

## License

MIT
