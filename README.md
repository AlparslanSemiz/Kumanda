<p align="center"><img src="assets/icon.png" width="128" alt="Kumanda icon"></p>

<h1 align="center">Kumanda</h1>
<p align="center">Use your Mac from the couch with a game controller.</p>
<p align="center"><a href="https://github.com/AlparslanSemiz/Kumanda/actions/workflows/build.yml"><img src="https://github.com/AlparslanSemiz/Kumanda/actions/workflows/build.yml/badge.svg" alt="build"></a></p>

Kumanda (Turkish for "remote control") is a small menu bar app for macOS. The left stick moves the pointer, the right stick scrolls, and the buttons click, switch Spaces and press keys. When a game comes to the front, Kumanda steps aside, so the game gets the controller to itself.

It works with any controller macOS supports: Xbox, PlayStation, 8BitDo and other MFi pads.

## Buttons

| Control | Action |
| --- | --- |
| Left stick | Move the pointer |
| Right stick | Scroll |
| A | Left click (hold to drag, press twice to double-click) |
| B | Right click |
| X | Esc |
| Y | ⌘ Space (Spotlight or Raycast) |
| Menu ☰ | Return |
| View ⧉ | Mission Control |
| LB / RB | Previous / next Space |
| D-pad | Arrow keys (hold to repeat) |
| Hold LT / RT | Slow, precise pointer / fast pointer |
| Press both sticks | Turn Kumanda on or off |

## Games get the controller

Kumanda pauses on its own while a game is in front. It recognises games by their App Store category. To add an app it misses, open the menu while that app is in front and choose **“… açıkken durdur”** (pause while … is open). Those apps are kept in `~/.config/kumanda/games.txt`, one bundle id per line.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/AlparslanSemiz/Kumanda/main/install.sh | zsh
```

The script builds Kumanda from source on your Mac, so it needs Apple's Command Line Tools. It installs the app to `~/Applications` and opens it. Then turn on **Kumanda** under System Settings → Privacy & Security → **Accessibility**. To start it at login, use the toggle in its menu.

The menu is in Turkish for now.

## Check what your controller sends

If a button does nothing, check whether macOS sees it at all:

```sh
swift tools/padtest.swift
```

It prints every press for two minutes. Back paddles, for example, usually send nothing until you map them to a button in the controller's own software.

## Keep the permission across rebuilds

If a code-signing certificate named "Veda Local Signing" exists (made by [Veda's](https://github.com/AlparslanSemiz/Veda) `scripts/make_signing_cert.sh`), `build.sh` signs with it. Otherwise the app is signed ad hoc, and macOS asks for Accessibility again after every rebuild.

## Uninstall

```sh
pkill -x Kumanda; rm -rf ~/Applications/Kumanda.app ~/.config/kumanda ~/.local/src/Kumanda
```

## Requirements

macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`).

## License

MIT
