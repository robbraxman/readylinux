# ReadyLinux — Selective Install

`install.sh` installs everything and changes everything, every time, with no way to say no to one piece. That's fine the first time on a clean machine. It's not fine on a machine that already has its own Brave, its own KeePassXC, its own wallpaper, or a 55" 4K display where "Large Text" is the last thing you want.

`install-selective.sh` is a separate entry point, not a patch to `install.sh`. It does not touch `install.sh` or `uninstall.sh`. Every line of logic that isn't about the two problems below is byte-for-byte what Rob wrote.

It solves two problems:

1. **It checks before it installs.** Each app is checked against dpkg/rpm, Flatpak (case-insensitive app id), snap, the command on `PATH`, `.desktop` files (system, snap, Flatpak, and `~/.local`), AppImages in `~/Applications` and `~/Downloads`, and `/opt`. Anything already present is left alone and never offered. This is what `install.sh` doesn't do — it installs Brave even if your real Brave is a Flatpak, Chrome even if your real Chrome is an apt package, and so on.
2. **It asks before it changes anything else.** Every app that's missing, and every non-app change the script makes, shows up on one configure screen. Everything starts checked. Uncheck what you don't want, and the rest of the script runs exactly as Rob wrote it.

## Running it

```bash
./install-selective.sh            # interactive: one configure screen (or y/N prompts, see below)
./install-selective.sh --check    # print what's present/missing and what would be offered; changes nothing
./install-selective.sh --yes      # accept everything missing/offered, no prompts
./install-selective.sh --no-apps  # install no apps; non-app changes are still offered normally
```

`--check` is read-only. No `sudo`, no `apt`, no file writes — safe to run any time just to see where a machine stands.

### The configure screen

If `zenity` is available and there's a display, one checklist window lists every missing app and every optional change, all pre-checked. Uncheck anything you don't want and click OK; the script proceeds with exactly what's left checked.

If there's no display or no `zenity` (headless, over plain SSH, or piped straight into `bash`), it falls back to a `y/N` prompt per item, read from `/dev/tty` so it still works even when the script itself is being read from stdin. The default answer is No.

`--no-apps` only forces the app list off — it does not skip the non-app changes. If you want nothing at all to happen, uncheck everything in the configure screen, or answer No to every prompt.

## What's optional

### Apps — skipped automatically if already present, by any method

- Brave
- Google Chrome
- Firefox
- Thunderbird
- KeePassXC
- KolourPaint
- VLC
- GDebi
- GNOME Disks
- Flatpak
- A text editor

### Non-app changes — offered every run (there's no "already applied" detection for these the way there is for apps, though the underlying commands are the same idempotent ones Rob already wrote — re-running with a change checked is still safe)

1. **IPv4 network preference**
2. **Lid-close behavior** — the laptop suspend rule; skip it on a desktop
3. **Media/AppFiles folders & bookmarks**
4. **USB auto-mount watcher**
5. **Convenience launchers** — Find my file, AppImage/ISO/.sh click-to-run, Brax.me. Bundled as one item on purpose: this is most people's actual reason for running the script, and splitting it into five tiny toggles would just be friction.
6. **Default apps** — browser, mail, video, `.deb`, `.rpm`
7. **Dock/panel pins**
8. **File manager window size**
9. **Text editor font & window size**
10. **Terminal size & colors**
11. **Screen scale** — this is the GNOME "Large Text" accessibility setting. Fine on a small high-res laptop screen; probably not what you want on a large 4K display with room to spare.
12. **Wallpaper** — skip it if yours isn't the stock distro default Rob's script is trying to replace.

## Known limits

- Selective gating only covers the apt/Ubuntu-family branch (Ubuntu, Zorin, Mint, Pop). The Fedora/`dnf` branch in `install.sh` is untouched and always runs its own unconditional installs if triggered on Fedora — `--no-apps`, `--yes`, and the configure screen do not reach it yet.
- The configure screen needs a graphical session, same as `install.sh`'s own existing `zenity` dialogs. Without one, it falls back to terminal prompts rather than failing.
- Two small bugs fixed along the way, both pre-existing in `install.sh`: the `flatpak remotes | grep -q flathub` check could abort the whole script under `set -e` if Flatpak wasn't installed, and that same pattern was vulnerable to a SIGPIPE/`pipefail` false failure. Both are now guarded and capture output into a variable before grepping it.

## Testing done

- `bash -n` and `shellcheck` both clean.
- Presence detection verified against this machine's real state (apt, Flatpak, snap, and "not installed at all" all exercised) and against synthetic stubs for dpkg/flatpak/snap.
- All four decision paths tested in isolation with a stub `zenity` (not the real binary, to avoid popping a dialog on a live desktop during testing): `--yes`, `--no-apps`, no-display/no-zenity fallback, and the checklist itself with items unchecked.
- `--check` run for real against a live machine; output cross-checked by hand against `dpkg-query`, `flatpak list`, and `snap list`.
- Not yet run for real end-to-end (no flags) — that's intentionally left for whoever is testing this before it ships.

## Why this file instead of editing README.md

This is deliberately a separate document, not an edit to Rob's `README.md`. He can fold in whatever parts of this he wants, in his own words, when and if he decides to merge any of it.
