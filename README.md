# Pipes

The classic 3D Pipes screensaver, rebuilt as a native macOS `.saver`. Pipes grow through a 3D grid, bend at elbow or ball joints, dissolve away in random blocks, and start again. Now and then, a teapot.

![Pipes screensaver](docs/screenshot.png)

It's plain Swift + SceneKit, with no web view, no network access and no dependencies.

**Open source and absolutely free.** It's released into the public domain under the [Unlicense](LICENSE). Use it, copy it, change it or sell it, for any purpose, with no attribution needed.

## Install

1. Download [`dist/Pipes-arm64.zip`](dist/Pipes-arm64.zip). It's for Apple Silicon Macs, on macOS 12 or later.
2. Unzip it and double-click `Pipes.saver`. When asked, install it for this user only.
3. Open **System Settings → Screen Saver** and pick **Pipes**.

The build is ad-hoc signed, not notarized, so macOS may block it the first time. See [Troubleshooting](#troubleshooting).

To check the download: `shasum -a 256 -c dist/Pipes-arm64.zip.sha256`

## Build from source

Requires Xcode or the Command Line Tools (`xcode-select --install`).

```bash
./build.sh                     # universal (Apple Silicon + Intel) → build/Pipes.saver
./build.sh install             # build and copy to ~/Library/Screen Savers
ARCHS=arm64 ./build.sh         # Apple Silicon only
```

## Options

Open them with **Screen Saver → Pipes → Options…**

| Option | Default | |
|---|---|---|
| Joints | Mixed | Elbow, Ball, Mixed, or Cycle (changes each round) |
| Growth speed | 25 cells/s | 5–80 |
| Pipes at once | 3 | 1–8 |
| Reset every | 25 s | 10–120 |
| Rotate camera | off | slow orbit |
| Teapots | on | 1-in-200 chance per turn; 1 round in 20 is a candy-cane round |

## Troubleshooting

**"Pipes.saver can't be opened" / "Apple could not verify…"**
Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. Or clear the download flag:
```bash
xattr -dr com.apple.quarantine ~/Library/Screen\ Savers/Pipes.saver
```

**The old version still shows after an update, or Pipes doesn't appear in the list**
Quit System Settings, then run `killall legacyScreenSaver` and reopen it. macOS caches loaded screensavers.

**"You cannot use the Pipes screen saver with this version of macOS"**
The zip is Apple Silicon only. On an Intel Mac, build from source with `./build.sh install`.

**Black screen, or high CPU after the screensaver ends**
This is a known bug in the macOS 14+ screensaver host. Pipes exits the host when the screensaver stops, but if anything gets stuck, `killall legacyScreenSaver` fixes it.

**Uninstall**
```bash
rm -rf ~/Library/Screen\ Savers/Pipes.saver
```

## Project layout

```
Sources/PipesEngine.swift      grid simulation, geometry, lighting, dissolve
Sources/PipesSaverView.swift   ScreenSaverView + Options sheet
Sources/Settings.swift         saved preferences
Sources/Teapot.swift           Utah teapot tessellation
Sources/UtahTeapotData.swift   teapot control points
tools/snapshot_main.swift      offscreen renderer (thumbnails, screenshots)
llms.txt                       project summary for AI assistants
```

## License

Public domain: [Unlicense](LICENSE). Pull requests and forks are welcome.

There's one exception. `Sources/UtahTeapotData.swift` holds the Utah teapot control points from three.js, which are MIT licensed. They're free to use as well; just keep their notice ([THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)) with that file.

## Credits

Inspired by the Windows NT 3D Pipes screensaver and [1j01/pipes](https://github.com/1j01/pipes). The code here is an independent implementation. By [TinKurbatoff](https://github.com/TinKurbatoff).
