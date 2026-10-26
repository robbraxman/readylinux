#!/usr/bin/env bash
# ReadyLinux — install
#
# Supported:
#   Ubuntu GNOME, Zorin, Linux Mint Cinnamon / MATE / Xfce,
#   Pop!_OS COSMIC, Fedora Workstation.
#
# Run:
#   wget -qO- https://raw.githubusercontent.com/robbraxman/readylinux/main/install.sh | bash
#
# What is the same on every distro:
#   Packages: Brave, Chrome, Firefox, Thunderbird, KeePassXC, KolourPaint, VLC.
#   Folders: ~/Media/Disks and ~/Documents/AppFiles, plus a sidebar bookmark.
#   USB watcher: refreshes Media when a disk is plugged in.
#   Find my file, Brax.me launcher, AppImage click-to-install.
#   Defaults: Brave for web, Thunderbird for mail, VLC for video.
#   IPv4 preferred, IPv6 left on. Lid sleeps on battery, stays awake on AC.
#
# What changes by distro or desktop:
#   Packages: apt on Ubuntu-family, dnf on Fedora. Fedora also installs Dash to Dock.
#   Dock: GNOME favorite-apps on Ubuntu, Zorin, Fedora. Cinnamon, MATE, and Xfce
#         use their own panel. COSMIC uses its own favorites file. Zorin’s layout
#         is not moved. Xfce pins are inserted, never a full panel rewrite.
#   Fedora has no dock until Dash to Dock is enabled. Icons are 40px.
#   Wallpaper: GNOME picture-uri, MATE picture-filename, Xfce per-monitor backdrop.
#   Terminal: Ptyxis on new Ubuntu, GNOME Terminal on Zorin and Mint, xfce4-terminal
#             on Xfce. Size 110x34, or 120x36 on Xfce. Colors are not forced.
#   Editor: GNOME Text Editor, or Xed on Mint. Font 12pt.
#   Scale: 125% on a laptop or 1080p. 100% on a 1440p or 4K desktop.
#   File manager: Nautilus, Nemo, Caja, Thunar, or COSMIC Files. Bookmarks are GTK.
#
# Known limits:
#   Zorin: panel layout is not touched. Pins are added only. Moving Zorin's
#          panel or taskbar breaks its Windows-style setup.
#   Xfce: the panel list is never rewritten. Replacing plugin-ids moves the
#         tray and leaves dead Show Apps icons. Pins are inserted if the
#         panel is already a normal launcher panel. Thunar does not remember
#         window position. Wallpaper is set per monitor and can miss if the
#         backdrop path is not the usual screen0/monitor path.
#   Fedora: custom partitioning is an Anaconda bug. Use a whole disk.
#            There is no dock until Dash to Dock is enabled.
#   GNOME: dock clicks can freeze until a logout after pins are written.
#   Colors are not forced on any terminal. The user keeps their palette.
#
# Mint's file manager may run this with sh. That fails on lines 9, 17, and 23.
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi
# Double-click in Files does nothing useful. Use install.desktop, or run in a terminal.
if [[ ! -t 1 ]]; then
  zenity --question --width=420 --title="ReadyLinux" \
    --text="This installs KeePassXC, KolourPaint, Chrome, VLC, Thunderbird, GDebi, Disks, and Flatpak.\n\nIt also sets folders, the dock, the lid rule, and Find my file.\n\nA terminal will open so you can enter your password. Continue?" \
    || exit 0
  term="$(command -v gnome-terminal || command -v x-terminal-emulator || true)"
  [[ -n "$term" ]] || { zenity --error --text="No terminal found."; exit 1; }
  exec "$term" -- bash -c "\"$0\"; echo; read -r -p 'Press Enter to close.'"
fi
set -euo pipefail

# Selective-install addition: flags. --yes accepts all missing apps,
# --no-apps installs none of them, --check only prints the presence table.
ASSUME_YES=0
NO_APPS=0
CHECK_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=1 ;;
    --no-apps) NO_APPS=1 ;;
    --check) CHECK_ONLY=1 ;;
  esac
done

SCALE="1.25"
WALLPAPER_URL="https://brax.me/readylinux/wallpaper.jpg"
BRAX_ICON_URL="https://brax.me/img/logo-b1a.png"
BRAX_URL="https://brax.me"

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }
need_cmd() { command -v "$1" >/dev/null 2>&1; }

if [[ "$(id -u)" -eq 0 ]]; then
  warn "Run as your user, not root. The script will ask for sudo."
  exit 1
fi

desktop_session() {
  printf '%s\n' "${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unknown}}"
}

# ---------------------------------------------------------------------------
# Selective-install addition: presence detection
# Checks dpkg/rpm, Flatpak (case-insensitive app id), snap, PATH, .desktop
# files (system, snap, Flatpak, ~/.local), AppImages (~/Applications,
# ~/Downloads), and /opt. Skips anything already present; asks before
# installing anything missing.
# ---------------------------------------------------------------------------
has_dpkg() { command -v dpkg >/dev/null 2>&1 && dpkg -s "$1" >/dev/null 2>&1; }
has_rpm()  { command -v rpm >/dev/null 2>&1 && rpm -q "$1" >/dev/null 2>&1; }
has_flatpak() {
  command -v flatpak >/dev/null 2>&1 || return 1
  local ids
  ids="$(flatpak list --app --columns=application 2>/dev/null || true)"
  printf '%s\n' "$ids" | grep -qi -- "$1"
}
has_snap() {
  command -v snap >/dev/null 2>&1 || return 1
  local names
  names="$(snap list 2>/dev/null | awk 'NR>1{print $1}' || true)"
  printf '%s\n' "$names" | grep -qix -- "$1"
}
has_desktop() {
  local pat="$1" dir hit
  for dir in /usr/share/applications /var/lib/snapd/desktop/applications \
             /var/lib/flatpak/exports/share/applications \
             "$HOME/.local/share/flatpak/exports/share/applications" \
             "$HOME/.local/share/applications"; do
    [[ -d "$dir" ]] || continue
    hit="$(find "$dir" -maxdepth 1 -iname "*${pat}*.desktop" 2>/dev/null | head -n1)"
    [[ -n "$hit" ]] && return 0
  done
  return 1
}
has_appimage() {
  local pat="$1" dir hit
  for dir in "$HOME/Applications" "$HOME/Downloads"; do
    [[ -d "$dir" ]] || continue
    hit="$(find "$dir" -maxdepth 1 \( -iname "*${pat}*.appimage" \) 2>/dev/null | head -n1)"
    [[ -n "$hit" ]] && return 0
  done
  return 1
}
has_opt() {
  local pat="$1" hit
  hit="$(find /opt -maxdepth 2 -iname "*${pat}*" 2>/dev/null | head -n1)"
  [[ -n "$hit" ]]
}
any_cmd()      { local c; for c in "$@"; do need_cmd "$c" && return 0; done; return 1; }
any_desktop()  { local p; for p in "$@"; do has_desktop "$p" && return 0; done; return 1; }

APPS=(brave chrome firefox thunderbird keepassxc kolourpaint vlc gdebi disks flatpak editor)
declare -A APP_LABEL=(
  [brave]="Brave" [chrome]="Google Chrome" [firefox]="Firefox"
  [thunderbird]="Thunderbird" [keepassxc]="KeePassXC" [kolourpaint]="KolourPaint"
  [vlc]="VLC" [gdebi]="GDebi" [disks]="GNOME Disks" [flatpak]="Flatpak"
  [editor]="Text editor"
)
declare -A APP_PRESENT=()
declare -A APP_SOURCE=()
declare -A APP_INSTALL=()

detect_app() {
  local app="$1" src=""
  case "$app" in
    brave)
      has_dpkg brave-browser && src="apt"
      [[ -z "$src" ]] && has_rpm brave-browser && src="rpm"
      [[ -z "$src" ]] && has_flatpak 'brave' && src="flatpak"
      [[ -z "$src" ]] && has_snap brave && src="snap"
      [[ -z "$src" ]] && any_cmd brave-browser brave && src="PATH"
      [[ -z "$src" ]] && has_desktop 'brave' && src="desktop file"
      [[ -z "$src" ]] && has_appimage 'brave' && src="AppImage"
      [[ -z "$src" ]] && has_opt 'brave' && src="/opt"
      ;;
    chrome)
      has_dpkg google-chrome-stable && src="apt"
      [[ -z "$src" ]] && has_rpm google-chrome-stable && src="rpm"
      [[ -z "$src" ]] && has_flatpak 'com.google.chrome' && src="flatpak"
      [[ -z "$src" ]] && has_snap chrome && src="snap"
      [[ -z "$src" ]] && any_cmd google-chrome-stable google-chrome && src="PATH"
      [[ -z "$src" ]] && has_desktop 'google-chrome' && src="desktop file"
      [[ -z "$src" ]] && has_appimage 'chrome' && src="AppImage"
      [[ -z "$src" ]] && has_opt 'chrome' && src="/opt"
      ;;
    firefox)
      has_dpkg firefox && src="apt"
      [[ -z "$src" ]] && has_rpm firefox && src="rpm"
      [[ -z "$src" ]] && has_flatpak 'firefox' && src="flatpak"
      [[ -z "$src" ]] && has_snap firefox && src="snap"
      [[ -z "$src" ]] && any_cmd firefox && src="PATH"
      [[ -z "$src" ]] && any_desktop 'firefox' && src="desktop file"
      [[ -z "$src" ]] && has_appimage 'firefox' && src="AppImage"
      [[ -z "$src" ]] && has_opt 'firefox' && src="/opt"
      ;;
    thunderbird)
      has_dpkg thunderbird && src="apt"
      [[ -z "$src" ]] && has_rpm thunderbird && src="rpm"
      [[ -z "$src" ]] && has_flatpak 'thunderbird' && src="flatpak"
      [[ -z "$src" ]] && has_snap thunderbird && src="snap"
      [[ -z "$src" ]] && any_cmd thunderbird && src="PATH"
      [[ -z "$src" ]] && any_desktop 'thunderbird' && src="desktop file"
      [[ -z "$src" ]] && has_appimage 'thunderbird' && src="AppImage"
      [[ -z "$src" ]] && has_opt 'thunderbird' && src="/opt"
      ;;
    keepassxc)
      has_dpkg keepassxc && src="apt"
      [[ -z "$src" ]] && has_rpm keepassxc && src="rpm"
      [[ -z "$src" ]] && has_flatpak 'keepassxc' && src="flatpak"
      [[ -z "$src" ]] && has_snap keepassxc && src="snap"
      [[ -z "$src" ]] && any_cmd keepassxc && src="PATH"
      [[ -z "$src" ]] && any_desktop 'keepassxc' && src="desktop file"
      [[ -z "$src" ]] && has_appimage 'keepassxc' && src="AppImage"
      [[ -z "$src" ]] && has_opt 'keepassxc' && src="/opt"
      ;;
    kolourpaint)
      has_dpkg kolourpaint && src="apt"
      [[ -z "$src" ]] && has_dpkg kolourpaint5 && src="apt"
      [[ -z "$src" ]] && has_rpm kolourpaint && src="rpm"
      [[ -z "$src" ]] && has_flatpak 'kolourpaint' && src="flatpak"
      [[ -z "$src" ]] && has_snap kolourpaint && src="snap"
      [[ -z "$src" ]] && any_cmd kolourpaint kolourpaint5 && src="PATH"
      [[ -z "$src" ]] && any_desktop 'kolourpaint' && src="desktop file"
      [[ -z "$src" ]] && has_appimage 'kolourpaint' && src="AppImage"
      [[ -z "$src" ]] && has_opt 'kolourpaint' && src="/opt"
      ;;
    vlc)
      has_dpkg vlc && src="apt"
      [[ -z "$src" ]] && has_rpm vlc && src="rpm"
      [[ -z "$src" ]] && has_flatpak 'vlc' && src="flatpak"
      [[ -z "$src" ]] && has_snap vlc && src="snap"
      [[ -z "$src" ]] && any_cmd vlc && src="PATH"
      [[ -z "$src" ]] && any_desktop 'vlc' && src="desktop file"
      [[ -z "$src" ]] && has_appimage 'vlc' && src="AppImage"
      [[ -z "$src" ]] && has_opt 'vlc' && src="/opt"
      ;;
    gdebi)
      has_dpkg gdebi && src="apt"
      [[ -z "$src" ]] && has_dpkg gdebi-core && src="apt"
      [[ -z "$src" ]] && any_cmd gdebi gdebi-gtk && src="PATH"
      [[ -z "$src" ]] && any_desktop 'gdebi' && src="desktop file"
      [[ -z "$src" ]] && has_opt 'gdebi' && src="/opt"
      ;;
    disks)
      has_dpkg gnome-disk-utility && src="apt"
      [[ -z "$src" ]] && has_rpm gnome-disk-utility && src="rpm"
      [[ -z "$src" ]] && any_cmd gnome-disks && src="PATH"
      [[ -z "$src" ]] && any_desktop 'gnome-disks' 'diskutility' && src="desktop file"
      ;;
    flatpak)
      has_dpkg flatpak && src="apt"
      [[ -z "$src" ]] && has_rpm flatpak && src="rpm"
      [[ -z "$src" ]] && need_cmd flatpak && src="PATH"
      ;;
    editor)
      any_cmd gnome-text-editor gedit xed pluma mousepad && src="PATH"
      [[ -z "$src" ]] && has_flatpak 'texteditor' && src="flatpak"
      [[ -z "$src" ]] && any_desktop 'org.gnome.texteditor' 'gedit' 'xed' 'pluma' 'mousepad' && src="desktop file"
      ;;
  esac
  APP_SOURCE[$app]="$src"
  [[ -n "$src" ]]
}

for app in "${APPS[@]}"; do
  if detect_app "$app"; then
    APP_PRESENT[$app]=1
  else
    APP_PRESENT[$app]=0
  fi
done

print_app_table() {
  printf '%-14s %-8s %s\n' "App" "Present" "Source"
  printf '%-14s %-8s %s\n' "---" "-------" "------"
  local app
  for app in "${APPS[@]}"; do
    if [[ "${APP_PRESENT[$app]}" == "1" ]]; then
      printf '%-14s %-8s %s\n' "${APP_LABEL[$app]}" "yes" "${APP_SOURCE[$app]}"
    else
      printf '%-14s %-8s %s\n' "${APP_LABEL[$app]}" "no" "-"
    fi
  done
}

# Selective-install addition: every non-app change Rob's script makes is
# also optional. CHANGE_APPLY[key] gates the matching section further down.
CHANGES=(ipv4 lid folders usbwatch shelltools defaults dock filemanager editorlook terminal scale wallpaper)
declare -A CHANGE_LABEL=(
  [ipv4]="IPv4 network preference"
  [lid]="Lid-close behavior (laptop suspend rule)"
  [folders]="Media/AppFiles folders & bookmarks"
  [usbwatch]="USB auto-mount watcher"
  [shelltools]="Convenience launchers (Find my file, AppImage/ISO/.sh click-to-run, Brax.me)"
  [defaults]="Default apps (browser, mail, video, .deb, .rpm)"
  [dock]="Dock/panel pins"
  [filemanager]="File manager window size"
  [editorlook]="Text editor font & window size"
  [terminal]="Terminal size & colors"
  [scale]="Screen scale (Large Text accessibility)"
  [wallpaper]="Wallpaper"
)
declare -A CHANGE_APPLY=()

print_changes_table() {
  local c
  for c in "${CHANGES[@]}"; do
    printf '%s\n' "${CHANGE_LABEL[$c]}"
  done
}

log "App presence"
print_app_table
log "Other changes (all optional)"
print_changes_table
if [[ "$CHECK_ONLY" == "1" ]]; then
  exit 0
fi

ask_install() {
  local label="$1" ans
  read -r -p "Apply: ${label}? [y/N] " ans < /dev/tty 2>/dev/tty || ans=""
  [[ "$ans" =~ ^[Yy]$ ]]
}

for app in "${APPS[@]}"; do
  [[ "${APP_PRESENT[$app]}" == "1" ]] && APP_INSTALL[$app]=0
done
missing_apps=()
for app in "${APPS[@]}"; do
  [[ "${APP_PRESENT[$app]}" == "0" ]] && missing_apps+=("$app")
done

# Selective-install addition: one configure screen for every optional app
# and change instead of a prompt per item. Everything starts checked;
# uncheck what you don't want. --no-apps only forces apps off; it does not
# touch the non-app changes. Falls back to the y/N prompts if zenity or a
# display isn't available.
pending_apps=()
pending_changes=("${CHANGES[@]}")
if [[ "$ASSUME_YES" == "1" ]]; then
  for app in "${missing_apps[@]}"; do APP_INSTALL[$app]=1; done
  for c in "${CHANGES[@]}"; do CHANGE_APPLY[$c]=1; done
  pending_changes=()
elif [[ "$NO_APPS" == "1" ]]; then
  for app in "${missing_apps[@]}"; do APP_INSTALL[$app]=0; done
else
  pending_apps=("${missing_apps[@]}")
fi

if [[ "${#pending_apps[@]}" -gt 0 || "${#pending_changes[@]}" -gt 0 ]]; then
  if need_cmd zenity && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    checklist_args=()
    for app in "${pending_apps[@]}"; do checklist_args+=(TRUE "${APP_LABEL[$app]}"); done
    for c in "${pending_changes[@]}"; do checklist_args+=(TRUE "${CHANGE_LABEL[$c]}"); done
    selected="$(zenity --list --checklist --width=520 --height=560 \
      --title="ReadyLinux — choose what to apply" \
      --text="Everything below starts checked. Uncheck anything you don't want." \
      --column="Apply" --column="Item" "${checklist_args[@]}" --separator='|' || true)"
    for app in "${pending_apps[@]}"; do
      if [[ "|${selected}|" == *"|${APP_LABEL[$app]}|"* ]]; then
        APP_INSTALL[$app]=1
      else
        APP_INSTALL[$app]=0
      fi
    done
    for c in "${pending_changes[@]}"; do
      if [[ "|${selected}|" == *"|${CHANGE_LABEL[$c]}|"* ]]; then
        CHANGE_APPLY[$c]=1
      else
        CHANGE_APPLY[$c]=0
      fi
    done
  else
    for app in "${pending_apps[@]}"; do
      if ask_install "${APP_LABEL[$app]}"; then
        APP_INSTALL[$app]=1
      else
        APP_INSTALL[$app]=0
      fi
    done
    for c in "${pending_changes[@]}"; do
      if ask_install "${CHANGE_LABEL[$c]}"; then
        CHANGE_APPLY[$c]=1
      else
        CHANGE_APPLY[$c]=0
      fi
    done
  fi
fi

# ---------------------------------------------------------------------------
# System packages
# Fedora uses dnf. Everything else uses apt.
# Chrome and Brave are added from their own repos. Fedora 41+ needs the
# dnf5 repo command. Cinnamon also gets Xed. Fedora gets Dash to Dock.
# ---------------------------------------------------------------------------
log "Installing packages"
# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}" in
  fedora)
    sudo dnf install -y \
      curl ca-certificates wget gnupg2 \
      zenity flatpak \
      keepassxc kolourpaint thunderbird firefox vlc gnome-text-editor gnome-disk-utility \
      gnome-shell-extension-dash-to-dock
    if ! rpm -q google-chrome-stable >/dev/null 2>&1; then
      log "Adding Google Chrome"
      sudo dnf install -y https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm
    fi
    if ! rpm -q brave-browser >/dev/null 2>&1; then
      log "Adding Brave"
      sudo dnf install -y dnf-plugins-core
      if dnf config-manager --help 2>&1 | grep -q addrepo; then
        sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
      else
        sudo dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
      fi
      sudo dnf install -y brave-browser
    fi
    ;;
  *)
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
      curl ca-certificates wget gnupg zenity
    # Selective-install addition: only install apps the user approved above.
    pkgs=()
    [[ "${APP_INSTALL[flatpak]}" == "1" ]] && pkgs+=(flatpak)
    [[ "${APP_INSTALL[gdebi]}" == "1" ]] && pkgs+=(gdebi)
    [[ "${APP_INSTALL[disks]}" == "1" ]] && pkgs+=(gnome-disk-utility)
    [[ "${APP_INSTALL[keepassxc]}" == "1" ]] && pkgs+=(keepassxc)
    [[ "${APP_INSTALL[kolourpaint]}" == "1" ]] && pkgs+=(kolourpaint)
    [[ "${APP_INSTALL[thunderbird]}" == "1" ]] && pkgs+=(thunderbird)
    [[ "${APP_INSTALL[firefox]}" == "1" ]] && pkgs+=(firefox)
    [[ "${APP_INSTALL[vlc]}" == "1" ]] && pkgs+=(vlc)
    if [[ "${#pkgs[@]}" -gt 0 ]]; then
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
    fi
    if [[ "${APP_INSTALL[editor]}" == "1" ]]; then
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y gnome-text-editor 2>/dev/null \
        || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y gedit 2>/dev/null \
        || true
    fi
    if [[ "${XDG_CURRENT_DESKTOP:-}${DESKTOP_SESSION:-}" == *[Cc]innamon* ]]; then
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y xed || true
    fi
    if [[ "${APP_INSTALL[chrome]}" == "1" ]] && ! dpkg -s google-chrome-stable >/dev/null 2>&1; then
      log "Adding Google Chrome"
      sudo mkdir -p /usr/share/keyrings /tmp
      curl -fsSL -o /tmp/google-chrome.pub https://dl.google.com/linux/linux_signing_key.pub
      sudo rm -f /usr/share/keyrings/google-chrome.gpg
      sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/google-chrome.gpg /tmp/google-chrome.pub
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
        | sudo tee /etc/apt/sources.list.d/google-chrome.list >/dev/null
      sudo apt-get update
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y google-chrome-stable
    fi
    if [[ "${APP_INSTALL[brave]}" == "1" ]] && ! dpkg -s brave-browser >/dev/null 2>&1; then
      log "Adding Brave"
      sudo mkdir -p /usr/share/keyrings
      curl -fsSL -o /tmp/brave-browser-archive-keyring.gpg \
        https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
      sudo cp /tmp/brave-browser-archive-keyring.gpg /usr/share/keyrings/brave-browser-archive-keyring.gpg
      echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" \
        | sudo tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
      sudo apt-get update
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y brave-browser
    fi
    ;;
esac

# Selective-install addition: guard against flatpak being absent (declined
# above) and against a SIGPIPE false failure from `flatpak remotes | grep -q`
# under set -o pipefail — capture the output into a variable first.
if command -v flatpak >/dev/null 2>&1; then
  flatpak_remotes="$(flatpak remotes 2>/dev/null || true)"
  if ! printf '%s\n' "$flatpak_remotes" | grep -q flathub; then
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
  fi
fi

# Ubuntu Snap Thunderbird stores mail outside the apt profile.
# Copy it when the apt profile is missing or still blank. Do not overwrite accounts.
snap_tb="$HOME/snap/thunderbird/common/.thunderbird"
if [[ -f "$snap_tb/profiles.ini" ]]; then
  blank=1
  if [[ -f "$HOME/.thunderbird/profiles.ini" ]]; then
    if grep -Rqs 'mail.accountmanager.accounts' "$HOME/.thunderbird" 2>/dev/null \
       && grep -Rqs 'mail.accountmanager.accounts=.*[a-zA-Z0-9]' "$HOME/.thunderbird" 2>/dev/null; then
      blank=0
    fi
  fi
  if [[ "$blank" == "1" ]]; then
    log "Copying Snap Thunderbird profile into the blank apt profile"
    mkdir -p "$HOME/.thunderbird"
    cp -a "$snap_tb"/. "$HOME/.thunderbird"/
  fi
fi
if [[ "${CHANGE_APPLY[ipv4]}" == "1" ]]; then
  if [[ -f /etc/gai.conf ]] && grep -q 'human-linux-ipv4' /etc/gai.conf; then
    log "IPv4 preference already set"
  else
    log "Prefer IPv4, leave IPv6 available"
    echo "precedence ::ffff:0:0/96  100  # human-linux-ipv4" | sudo tee -a /etc/gai.conf >/dev/null
  fi
fi

# Lid: suspend on battery, awake on AC and dock. Do not restart logind.
if [[ "${CHANGE_APPLY[lid]}" == "1" ]]; then
  log "Lid close rule (applies on next reboot)"
  sudo mkdir -p /etc/systemd/logind.conf.d
  sudo tee /etc/systemd/logind.conf.d/human-linux-lid.conf >/dev/null <<'EOF'
[Login]
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
fi

# ---------------------------------------------------------------------------
# Folders and sidebar
# Same on every distro. ~/Media/Disks links extra disks and USB.
# ~/Documents/AppFiles links Snap, Flatpak, debs, and rpms.
# Bookmarks are GTK, so Nautilus, Nemo, Caja, and Thunar all see them.
# KDE places are written later, in the desktop branch.
# ---------------------------------------------------------------------------
refresh_media_links() {
  local user src d gvfs mtp dev mp fstype
  user="$(id -un)"
  mkdir -p "$HOME/Media/Disks"
  # Mount extra data partitions (NVMe, internal). Skip system, swap, and optical.
  if command -v lsblk >/dev/null && command -v udisksctl >/dev/null; then
    while read -r dev fstype label mp; do
      [[ -n "$dev" && -n "$fstype" ]] || continue
      [[ "$fstype" == "swap" || "$fstype" == "iso9660" ]] && continue
      case "$mp" in
        /|/boot|/boot/efi|/home) continue ;;
      esac
      [[ -n "$mp" ]] && continue
      case "${label,,}" in
        boot|efi|esp|system|recovery|winre|winre_drv|"microsoft reserved"|reserved) continue ;;
      esac
      udisksctl mount -b "$dev" >/dev/null 2>&1 || true
    done < <(lsblk -pnr -o PATH,FSTYPE,LABEL,MOUNTPOINT)
  fi
  find "$HOME/Media/Disks" -maxdepth 1 -type l -delete 2>/dev/null || true
  find "$HOME/Media/USB" -maxdepth 1 -type l -delete 2>/dev/null || true
  rmdir "$HOME/Media/USB" 2>/dev/null || true
  for src in "/media/$user" "/run/media/$user"; do
    [[ -d "$src" ]] || continue
    for d in "$src"/*; do
      [[ -e "$d" ]] || continue
      case "$(basename "$d" | tr '[:upper:]' '[:lower:]')" in
        boot|efi|esp|system|recovery|winre|winre_drv) continue ;;
      esac
      ln -sfn "$d" "$HOME/Media/Disks/$(basename "$d")"
    done
  done
  gvfs="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gvfs"
  rm -f "$HOME/Media/Phone"
  if [[ -d "$gvfs" ]]; then
    mtp="$(find "$gvfs" -maxdepth 1 \( -iname '*mtp*' -o -iname '*gphoto*' -o -iname '*afc*' \) 2>/dev/null | head -n1 || true)"
    if [[ -n "${mtp:-}" && -e "$mtp" ]]; then
      ln -sfn "$mtp" "$HOME/Media/Phone"
    fi
  fi
}

refresh_appfiles() {
  local dest="$HOME/Documents/AppFiles" d name
  mkdir -p "$dest" "$dest/debs" "$dest/rpms" "$dest/appimages"
  if [[ -d "$HOME/snap" ]]; then
    for d in "$HOME/snap"/*; do
      [[ -d "$d" ]] || continue
      name="$(basename "$d")"
      [[ "$name" == "README" ]] && continue
      [[ -e "$d/current" ]] && ln -sfn "$d/current" "$dest/${name}"
      [[ -d "$d/common" ]] && ln -sfn "$d/common" "$dest/${name}-common"
    done
  fi
  if [[ -d "$HOME/.var/app" ]]; then
    for d in "$HOME/.var/app"/*; do
      [[ -d "$d" ]] || continue
      name="$(basename "$d")"
      ln -sfn "$d" "$dest/flatpak-${name}"
    done
  fi
  if [[ -d "$HOME/Downloads" ]]; then
    for d in "$HOME/Downloads"/*.deb "$HOME/Downloads"/*.Deb; do
      [[ -e "$d" ]] || continue
      ln -sfn "$d" "$dest/debs/$(basename "$d")"
    done
    for d in "$HOME/Downloads"/*.rpm "$HOME/Downloads"/*.RPM; do
      [[ -e "$d" ]] || continue
      ln -sfn "$d" "$dest/rpms/$(basename "$d")"
    done
  fi
}

bookmark() {
  local uri="$1" label="$2" f
  for f in "$HOME/.config/gtk-3.0/bookmarks" "$HOME/.config/gtk-4.0/bookmarks"; do
    mkdir -p "$(dirname "$f")"
    touch "$f"
    grep -qF "$uri" "$f" || echo "$uri $label" >> "$f"
  done
}

if [[ "${CHANGE_APPLY[folders]}" == "1" ]]; then
  log "Folders and sidebar"
  xdg-user-dirs-update || true
  mkdir -p "$HOME/Media/Disks" "$HOME/Videos/OBS" "$HOME/Documents/AppFiles"
  refresh_media_links
  refresh_appfiles
  bookmark "file://$HOME/Media" "Media"
  bookmark "file://$HOME/Documents/AppFiles" "AppFiles"
  bookmark "file:///" "File System"
fi

# ---------------------------------------------------------------------------
# USB watcher
# User systemd service. Refreshes Media on udisks events and every 5 seconds.
# Same on every distro. Needs a desktop login, not a raw TTY.
# ---------------------------------------------------------------------------
if [[ "${CHANGE_APPLY[usbwatch]}" == "1" ]]; then
log "USB watcher"
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
cat > "$HOME/.local/bin/human-linux-usb-watch" <<'EOF'
#!/usr/bin/env bash
refresh() {
  local user src d gvfs mtp dev mp fstype
  user="$(id -un)"
  mkdir -p "$HOME/Media/Disks"
  if command -v lsblk >/dev/null && command -v udisksctl >/dev/null; then
    while read -r dev fstype label mp; do
      [[ -n "$dev" && -n "$fstype" ]] || continue
      [[ "$fstype" == "swap" || "$fstype" == "iso9660" ]] && continue
      case "$mp" in
        /|/boot|/boot/efi|/home) continue ;;
      esac
      [[ -n "$mp" ]] && continue
      case "${label,,}" in
        boot|efi|esp|system|recovery|winre|winre_drv|"microsoft reserved"|reserved) continue ;;
      esac
      udisksctl mount -b "$dev" >/dev/null 2>&1 || true
    done < <(lsblk -pnr -o PATH,FSTYPE,LABEL,MOUNTPOINT)
  fi
  find "$HOME/Media/Disks" -maxdepth 1 -type l -delete 2>/dev/null || true
  find "$HOME/Media/USB" -maxdepth 1 -type l -delete 2>/dev/null || true
  rmdir "$HOME/Media/USB" 2>/dev/null || true
  for src in "/media/$user" "/run/media/$user"; do
    [[ -d "$src" ]] || continue
    for d in "$src"/*; do
      [[ -e "$d" ]] || continue
      case "$(basename "$d" | tr '[:upper:]' '[:lower:]')" in
        boot|efi|esp|system|recovery|winre|winre_drv) continue ;;
      esac
      ln -sfn "$d" "$HOME/Media/Disks/$(basename "$d")"
    done
  done
  gvfs="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gvfs"
  rm -f "$HOME/Media/Phone"
  if [[ -d "$gvfs" ]]; then
    mtp="$(find "$gvfs" -maxdepth 1 \( -iname '*mtp*' -o -iname '*gphoto*' -o -iname '*afc*' \) 2>/dev/null | head -n1 || true)"
    if [[ -n "${mtp:-}" && -e "$mtp" ]]; then
      ln -sfn "$mtp" "$HOME/Media/Phone"
    fi
  fi
}
refresh
# udisks events, plus a poll, so a missed mount still shows up.
( while true; do sleep 5; refresh; done ) &
udisksctl monitor | while read -r line; do
  case "$line" in
    *Added*|*Removed*|*mounted*|*unmounted*|*Properties\ Changed*) refresh ;;
  esac
done
EOF
chmod +x "$HOME/.local/bin/human-linux-usb-watch"
cat > "$HOME/.config/systemd/user/human-linux-usb-watch.service" <<EOF
[Unit]
Description=Refresh ReadyLinux Media links
After=graphical-session.target
[Service]
ExecStart=$HOME/.local/bin/human-linux-usb-watch
Restart=always
RestartSec=3
[Install]
WantedBy=default.target
EOF
systemctl --user disable --now usb-watch.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/usb-watch.service" "$HOME/.local/bin/usb-watch"
systemctl --user daemon-reload || true
systemctl --user enable human-linux-usb-watch.service || true
systemctl --user restart human-linux-usb-watch.service || warn "Disk watcher not started. Log in on the desktop and rerun."
fi

# ---------------------------------------------------------------------------
# Find my file
# A small search GUI in Show Apps. Same on every distro.
# ---------------------------------------------------------------------------
if [[ "${CHANGE_APPLY[shelltools]}" == "1" ]]; then
log "Find my file"
cat > "$HOME/.local/bin/where-is-my-file" <<'EOF'
#!/usr/bin/env bash
q="${1:-}"
[[ -n "$q" ]] || { echo "usage: where-is-my-file <name>"; exit 1; }
roots=(
  "$HOME/Documents" "$HOME/Downloads" "$HOME/Videos" "$HOME/Pictures"
  "$HOME/Desktop" "$HOME/Media" "$HOME/Documents/AppFiles"
  "$HOME/snap" "$HOME/.var/app"
)
find "${roots[@]}" -iname "*${q}*" 2>/dev/null | head -n 50
EOF
chmod +x "$HOME/.local/bin/where-is-my-file"
cat > "$HOME/.local/bin/where-is-my-file-gui" <<'EOF'
#!/usr/bin/env bash
q="$(zenity --entry --title="Find my file" --text="Name or part of a name" --ok-label="Search" --cancel-label="Cancel")" || exit 0
[[ -z "$q" ]] && exit 0
hits="$("$HOME/.local/bin/where-is-my-file" "$q")"
if [[ -z "$hits" ]]; then
  zenity --info --title="Find my file" --text="No matches for: $q" --ok-label="OK"
  exit 0
fi
zenity --info --title="Find my file: $q" --ok-label="OK" --width=700 --text="$hits"
EOF
chmod +x "$HOME/.local/bin/where-is-my-file-gui"
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/where-is-my-file.desktop" <<EOF
[Desktop Entry]
Name=Find my file
Comment=Search Documents, Media, Snap and Flatpak folders
Exec=$HOME/.local/bin/where-is-my-file-gui
Terminal=false
Type=Application
Icon=system-search
Categories=Utility;
X-ReadyLinux=true
EOF

# ---------------------------------------------------------------------------
# AppImage launchers
# Clicking an AppImage copies it to ~/Applications, makes a desktop file,
# and links it under AppFiles. Same on every distro.
# ---------------------------------------------------------------------------
log "AppImage launchers"
mkdir -p "$HOME/Applications" "$HOME/.local/share/icons" "$HOME/Documents/AppFiles/appimages"
integrate_appimage() {
  local src="$1" base name dest icon
  [[ -f "$src" && ! -L "$src" ]] || return 0
  base="$(basename "$src")"
  name="${base%.[Aa]pp[Ii]mage}"
  dest="$HOME/Applications/$base"
  if [[ "$src" != "$dest" ]]; then
    mv "$src" "$dest"
  fi
  chmod +x "$dest" || true
  ln -sfn "$dest" "$HOME/Documents/AppFiles/appimages/$base" || true
  desk="$HOME/.local/share/applications/human-linux-appimage-${name}.desktop"
  cat > "$desk" <<EOF
[Desktop Entry]
Name=$name
Exec=$dest
Icon=application-x-executable
Terminal=false
Type=Application
Categories=Utility;
StartupNotify=true
EOF
  chmod +x "$desk" || true
  gio set "$desk" metadata::trusted true 2>/dev/null || true
  (
    cd /tmp
    rm -rf squashfs-root
    "$dest" --appimage-extract >/dev/null 2>&1 || true
    found=""
    if [[ -e squashfs-root/.DirIcon ]]; then
      found="$(readlink -f squashfs-root/.DirIcon)"
    fi
    if [[ ! -s "$found" ]]; then
      found="$(find squashfs-root -type f \( -iname '*.png' -o -iname '*.svg' \) 2>/dev/null | head -n1)"
    fi
    if [[ -s "$found" ]]; then
      cp -f "$found" "$icon"
      sed -i "s|^Icon=.*|Icon=$icon|" "$HOME/.local/share/applications/human-linux-appimage-${name}.desktop"
    fi
    rm -rf squashfs-root
  ) || true
  echo "integrated $base"
}
shopt -s nullglob
for d in "$HOME/Downloads"/*.AppImage "$HOME/Downloads"/*.appimage \
         "$HOME/Applications"/*.AppImage "$HOME/Applications"/*.appimage; do
  integrate_appimage "$d"
done
shopt -u nullglob

# ---------------------------------------------------------------------------
# Brax.me
# A site-as-app launcher. Same on every distro that has Brave or Chrome.
# ---------------------------------------------------------------------------
log "Brax.me launcher"
browser="$(command -v brave-browser || command -v google-chrome-stable || command -v google-chrome || true)"
if [[ -n "$browser" ]]; then
  mkdir -p "$HOME/.local/share/icons"
  curl -fsSL -o "$HOME/.local/share/icons/brax-me.png" "$BRAX_ICON_URL" || warn "Brax icon download failed"
  cat > "$HOME/.local/share/applications/brax-me.desktop" <<EOF
[Desktop Entry]
Name=Brax.me
Comment=brax.me
Exec=$browser --app=$BRAX_URL
Icon=$HOME/.local/share/icons/brax-me.png
Terminal=false
Type=Application
Categories=Network;
StartupNotify=true
X-ReadyLinux=true
EOF
fi
fi

# ---------------------------------------------------------------------------
# Defaults
# Brave for http/https, Thunderbird for mailto, VLC for video.
# .deb opens in GDebi on apt distros. .rpm opens in GNOME Software on Fedora.
# .iso opens in Disks. .sh opens the Run or Edit launcher.
# ---------------------------------------------------------------------------
desktop_id_exists() {
  local id="$1" f
  for f in "/usr/share/applications/${id}" "$HOME/.local/share/applications/${id}" \
           "/var/lib/flatpak/exports/share/applications/${id}"; do
    [[ -f "$f" ]] && return 0
  done
  return 1
}
first_existing_desktop() {
  local id
  for id in "$@"; do
    if desktop_id_exists "$id"; then
      printf '%s\n' "$id"
      return 0
    fi
  done
  return 1
}

if [[ "${CHANGE_APPLY[defaults]}" == "1" ]]; then
log "Default browser and mail"
if id="$(first_existing_desktop brave-browser.desktop com.brave.Browser.desktop)"; then
  xdg-settings set default-web-browser "$id" || true
  xdg-mime default "$id" x-scheme-handler/http || true
  xdg-mime default "$id" x-scheme-handler/https || true
  xdg-mime default "$id" text/html || true
else
  warn "Brave not installed; default browser unchanged"
fi
if id="$(first_existing_desktop thunderbird.desktop org.mozilla.Thunderbird.desktop)"; then
  xdg-mime default "$id" x-scheme-handler/mailto || true
fi
if id="$(first_existing_desktop vlc.desktop)"; then
  for mime in video/mp4 video/x-matroska video/x-msvideo video/webm; do
    xdg-mime default "$id" "$mime" || true
  done
fi
if id="$(first_existing_desktop gdebi.desktop)"; then
  python3 - "$id" <<'PY' || true
from pathlib import Path
import sys
app = sys.argv[1]
home = Path.home()
files = [
    home/".config/mimeapps.list",
    home/".config/gnome-mimeapps.list",
    home/".local/share/applications/mimeapps.list",
    home/".local/share/applications/defaults.list",
]
mimes = ("application/vnd.debian.binary-package", "application/x-deb")
for f in files:
    f.parent.mkdir(parents=True, exist_ok=True)
    text = f.read_text() if f.is_file() else ""
    lines = [ln for ln in text.splitlines() if not ln.startswith(mimes)]
    if "[Default Applications]" not in "\n".join(lines):
        lines.append("[Default Applications]")
    out = []
    for ln in lines:
        out.append(ln)
        if ln.strip() == "[Default Applications]":
            for mime in mimes:
                out.append(f"{mime}={app}")
    f.write_text("\n".join(out) + "\n")
print("deb handler", app)
PY
  xdg-mime default "$id" application/vnd.debian.binary-package || true
  xdg-mime default "$id" application/x-deb || true
fi
if id="$(first_existing_desktop org.gnome.Software.desktop gnome-software.desktop)"; then
  for mime in application/x-rpm application/x-redhat-package-manager; do
    xdg-mime default "$id" "$mime" || true
  done
fi
fi

if [[ "${CHANGE_APPLY[shelltools]}" == "1" ]]; then
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
cat > "$HOME/.local/bin/open-appimage" <<'EOF'
#!/usr/bin/env bash
f="${1:-}"
[[ -n "$f" && -f "$f" ]] || exit 1
base="$(basename "$f")"
name="${base%.[Aa]pp[Ii]mage}"
mkdir -p "$HOME/Applications" "$HOME/.local/share/icons" "$HOME/Documents/AppFiles/appimages"
dest="$HOME/Applications/$base"
if [[ "$f" != "$dest" ]]; then
  mv "$f" "$dest"
fi
chmod +x "$dest" || true
ln -sfn "$dest" "$HOME/Documents/AppFiles/appimages/$base"
icon="$HOME/.local/share/icons/${name}.png"
cat > "$HOME/.local/share/applications/human-linux-appimage-${name}.desktop" <<DESK
[Desktop Entry]
Name=$name
Exec=$dest
Icon=application-x-executable
Terminal=false
Type=Application
Categories=Utility;
X-ReadyLinux=true
DESK
( cd /tmp && rm -rf squashfs-root
  "$dest" --appimage-extract >/dev/null 2>&1 || true
  found=""
  if [[ -e squashfs-root/.DirIcon ]]; then
    found="$(readlink -f squashfs-root/.DirIcon)"
  fi
  if [[ ! -s "$found" ]]; then
    found="$(find squashfs-root -type f \( -iname '*.png' -o -iname '*.svg' \) 2>/dev/null | head -n1)"
  fi
  if [[ -s "$found" ]]; then
    cp -f "$found" "$icon"
    sed -i "s|^Icon=.*|Icon=$icon|" "$HOME/.local/share/applications/human-linux-appimage-${name}.desktop"
  fi
  rm -rf squashfs-root )
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
exec "$dest"
EOF
chmod +x "$HOME/.local/bin/open-appimage"
cat > "$HOME/.local/share/applications/open-appimage.desktop" <<EOF
[Desktop Entry]
Name=Install AppImage
Exec=$HOME/.local/bin/open-appimage %f
Terminal=false
Type=Application
MimeType=application/vnd.appimage;application/x-iso9660-appimage;application/x-executable;
NoDisplay=true
X-ReadyLinux=true
EOF
mkdir -p "$HOME/.local/share/mime/packages"
cat > "$HOME/.local/share/mime/packages/appimage.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/vnd.appimage">
    <comment>AppImage</comment>
    <glob pattern="*.AppImage"/>
    <glob pattern="*.appimage"/>
  </mime-type>
</mime-info>
EOF
update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
xdg-mime default open-appimage.desktop application/vnd.appimage || true
xdg-mime default open-appimage.desktop application/x-iso9660-appimage || true
# An executable AppImage is launched by Files and skips this handler.
# Leave Downloads copies non-executable so a click installs them.
shopt -s nullglob
for d in "$HOME/Downloads"/*.AppImage "$HOME/Downloads"/*.appimage; do
  chmod a-x "$d" 2>/dev/null || true
done
shopt -u nullglob
if id="$(first_existing_desktop gnome-disk-image-writer.desktop org.gnome.DiskUtility.desktop)"; then
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
  cat > "$HOME/.local/bin/open-iso" <<'EOF'
#!/usr/bin/env bash
iso="${1:-}"
[[ -n "$iso" && -f "$iso" ]] || exit 1
real="$(readlink -f "$iso")"
# Files mounts the ISO on click. Disk Image Writer errors if it is mounted.
while read -r loop back; do
  [[ "$back" == "$real" ]] || continue
  udisksctl unmount -b "$loop" >/dev/null 2>&1 || umount -l "$loop" >/dev/null 2>&1 || true
  udisksctl loop-delete -b "$loop" >/dev/null 2>&1 || losetup -d "$loop" >/dev/null 2>&1 || true
done < <(losetup -lnO NAME,BACK-FILE 2>/dev/null || true)
# A restore fails if the USB stick is still mounted. Unmount removable disks only.
while read -r dev rm; do
  [[ "$rm" == "1" ]] || continue
  while read -r part mp; do
    [[ -n "$mp" ]] || continue
    udisksctl unmount -b "$part" >/dev/null 2>&1 || umount -l "$part" >/dev/null 2>&1 || true
  done < <(lsblk -pnr -o PATH,MOUNTPOINT "$dev")
done < <(lsblk -dnr -o PATH,RM)
if command -v gnome-disk-image-writer >/dev/null; then
  exec gnome-disk-image-writer "$iso"
fi
exec gnome-disks
EOF
  chmod +x "$HOME/.local/bin/open-iso"
  cat > "$HOME/.local/share/applications/open-iso.desktop" <<EOF
[Desktop Entry]
Name=Write ISO to USB
Exec=$HOME/.local/bin/open-iso %f
Terminal=false
Type=Application
MimeType=application/x-cd-image;application/x-iso9660-image;application/vnd.efi.iso;application/x-raw-disk-image;
NoDisplay=true
X-ReadyLinux=true
EOF
  for mime in application/x-cd-image application/x-iso9660-image application/vnd.efi.iso application/x-raw-disk-image; do
    xdg-mime default open-iso.desktop "$mime" || true
  done
fi
fi

# ---------------------------------------------------------------------------
# Dock, scale, wallpaper, editor, terminal
# Desktop branch:
#   cosmic   COSMIC favorites file and Files sidebar
#   cinnamon Cinnamon panel pins
#   mate     MATE panel pins, 40px
#   xfce     Whisker favorites, left-side pins, tray on the right. No rewrite.
#   zorin    GNOME pins only. Panel layout is left alone.
#   kde      Places file only. Panel is left alone.
#   *        GNOME pins. Fedora enables Dash to Dock at 40px.
# Scale is 125% on a laptop or 1080p, 100% otherwise.
# Wallpaper is set on GNOME, MATE, and Xfce. Already-ours is left alone.
# ---------------------------------------------------------------------------
log "Session settings"
de="$(desktop_session | tr '[:upper:]' '[:lower:]')"

if [[ "${CHANGE_APPLY[dock]}" == "1" ]]; then
pin_gnome() {
  need_cmd gsettings || return 0
  need_cmd python3 || return 0
  local schema="$1"
  local files="$2"
  local editor="$3"
  gsettings writable "$schema" favorite-apps >/dev/null 2>&1 || return 0
  gsettings list-keys "$schema" 2>/dev/null | grep -qx favorite-apps || return 0
  python3 - "$schema" "$files" "$editor" <<'PY'
import ast, subprocess, sys
schema, files, editor = sys.argv[1:]
wanted = [
  "brave-browser.desktop",
  "google-chrome.desktop",
  editor,
  files,
  "org.gnome.Calculator.desktop",
  "org.gnome.Terminal.desktop",
]
# Browsers and mail by real filename. Zorin may not use firefox.desktop.
import pathlib
def first_named(word):
    for folder in (
        pathlib.Path("/usr/share/applications"),
        pathlib.Path("/var/lib/snapd/desktop/applications"),
        pathlib.Path.home()/".local/share/applications",
    ):
        if not folder.is_dir():
            continue
        for f in sorted(folder.glob("*.desktop")):
            if word in f.name.lower():
                return f.name
    return None
browser = first_named("firefox")
if browser:
    wanted.insert(2, browser)
mail = first_named("thunderbird")
if mail:
    wanted.insert(3, mail)
wanted.insert(4, "org.keepassxc.KeePassXC.desktop")
wanted.insert(5, "libreoffice-writer.desktop")
raw = subprocess.check_output(["gsettings", "get", schema, "favorite-apps"], text=True)
try:
    cur = ast.literal_eval(raw.strip())
except Exception:
    cur = []
if not isinstance(cur, list):
    cur = []
rest = [x for x in cur if x not in wanted]
out = []
for x in wanted:
    if x in ("", "None"):
        continue
    p1 = pathlib.Path("/usr/share/applications") / x
    p2 = pathlib.Path.home() / ".local/share/applications" / x
    p3 = pathlib.Path("/var/lib/snapd/desktop/applications") / x
    if p1.is_file() or p2.is_file() or p3.is_file():
        out.append(x)
out += [x for x in rest if x not in out]
repr_out = "[" + ", ".join("'" + x.replace("'", "") + "'" for x in out) + "]"
subprocess.check_call(["gsettings", "set", schema, "favorite-apps", repr_out])
print("pinned", repr_out)
PY
  # AppImages belong in Show Apps, not on the dock.
  python3 - "$schema" <<'PY' || true
import ast, subprocess, sys
schema = sys.argv[1]
raw = subprocess.check_output(["gsettings", "get", schema, "favorite-apps"], text=True)
try:
    cur = ast.literal_eval(raw.strip())
except Exception:
    cur = []
if isinstance(cur, list):
    out = [x for x in cur if "appimage" not in x.lower()]
    if out != cur:
        repr_out = "[" + ", ".join("'" + x.replace("'", "") + "'" for x in out) + "]"
        subprocess.check_call(["gsettings", "set", schema, "favorite-apps", repr_out])
        print("unpinned appimages", repr_out)
PY
}

case "$de" in
  *cosmic*)
    log "COSMIC dock and Files sidebar"
    fav="$HOME/.config/cosmic/com.system76.CosmicAppList/v1/favorites"
    mkdir -p "$(dirname "$fav")"
    python3 - "$fav" <<'PY' || true
import json, os, sys
from pathlib import Path
path = sys.argv[1]
candidates = [
  "brave-browser", "com.brave.Browser",
  "google-chrome", "com.google.Chrome",
  "firefox", "thunderbird", "org.mozilla.Thunderbird",
  "org.keepassxc.KeePassXC", "libreoffice-writer",
  "com.system76.CosmicEdit", "org.gnome.TextEditor",
  "com.system76.CosmicFiles", "org.gnome.Nautilus",
  "org.gnome.Calculator",
  "com.system76.CosmicStore",
  "com.system76.CosmicTerm",
  "com.system76.CosmicSettings",
]
def exists(appid):
    return Path(f"/usr/share/applications/{appid}.desktop").is_file() or Path.home().joinpath(f".local/share/applications/{appid}.desktop").is_file()
wanted = []
seen = set()
for appid in candidates:
    if appid in seen or not exists(appid):
        continue
    wanted.append(appid)
    seen.add(appid)
cur = []
if os.path.exists(path):
    try:
        cur = json.load(open(path))
    except Exception:
        cur = []
if not isinstance(cur, list):
    cur = []
rest = [x for x in cur if x not in wanted]
json.dump(wanted + rest, open(path, "w"), indent=4)
print("cosmic dock", wanted)
PY
    files_fav="$HOME/.config/cosmic/com.system76.CosmicFiles/v1/favorites"
    mkdir -p "$(dirname "$files_fav")"
    if [[ ! -f "$files_fav" ]]; then
      cat > "$files_fav" <<EOF
[
    Home,
    Documents,
    Downloads,
    Pictures,
    Videos,
    Path("$HOME/Media"),
    Path("$HOME/Documents/AppFiles"),
    Path("/"),
]
EOF
    else
      grep -q "$HOME/Media" "$files_fav" || sed -i "s/\]/    Path(\"$HOME\/Media\"),\n]/" "$files_fav"
      grep -q "$HOME/Documents/AppFiles" "$files_fav" || sed -i "s/\]/    Path(\"$HOME\/Documents\/AppFiles\"),\n]/" "$files_fav"
    fi
    ;;
  *cinnamon*)
    log "Cinnamon panel pins"
    python3 - <<'PY' || true
import json
from pathlib import Path
wanted = [
  "brave-browser.desktop", "google-chrome.desktop", "firefox.desktop",
  "thunderbird.desktop", "org.keepassxc.KeePassXC.desktop",
  "libreoffice-writer.desktop",
]
for editor in ("xed.desktop", "org.gnome.TextEditor.desktop", "gedit.desktop"):
    if Path("/usr/share/applications", editor).is_file():
        wanted.append(editor)
        break
wanted += ["nemo.desktop", "org.gnome.Calculator.desktop", "org.gnome.Terminal.desktop"]
roots = [
  Path.home() / ".config/cinnamon/spices/grouped-window-list@cinnamon.org",
  Path.home() / ".cinnamon/configs/grouped-window-list@cinnamon.org",
]
files = []
for root in roots:
    if root.is_dir():
        files.extend(root.glob("*.json"))
if not files:
    print("no cinnamon panel config")
else:
    for f in files:
        try:
            data = json.loads(f.read_text())
        except Exception:
            continue
        pin = data.get("pinned-apps")
        cur = []
        if isinstance(pin, dict):
            cur = pin.get("value") or pin.get("default") or []
            pin["value"] = wanted + [x for x in cur if x not in wanted]
        elif isinstance(pin, list):
            data["pinned-apps"] = wanted + [x for x in pin if x not in wanted]
        else:
            data["pinned-apps"] = {"value": wanted}
        f.write_text(json.dumps(data, indent=4))
        print("cinnamon panel", f)
PY
    # The running panel keeps the old list until it is reloaded.
    cinnamon --replace >/dev/null 2>&1 &
    ;;
  *mate*)
    log "MATE menu pins"
    if gsettings list-schemas | grep -qx 'com.linuxmint.mintmenu.plugins.applications'; then
      python3 - <<'PY' || true
import ast, subprocess
from pathlib import Path
schema = "com.linuxmint.mintmenu.plugins.applications"
key = "favorite-apps-list"
wanted = [
  "brave-browser.desktop", "google-chrome.desktop", "firefox.desktop",
  "thunderbird.desktop", "org.keepassxc.KeePassXC.desktop",
  "libreoffice-writer.desktop",
]
for editor in ("xed.desktop", "pluma.desktop", "org.gnome.TextEditor.desktop"):
    if Path("/usr/share/applications", editor).is_file():
        wanted.append(editor)
        break
wanted += ["caja.desktop", "org.gnome.Calculator.desktop", "mate-terminal.desktop"]
raw = subprocess.check_output(["gsettings", "get", schema, key], text=True).strip()
try:
    cur = ast.literal_eval(raw)
except Exception:
    cur = []
if not isinstance(cur, list):
    cur = []
rest = [x for x in cur if x not in wanted and x not in ("org.gnome.Nautilus.desktop", "nemo.desktop")]
out = wanted + rest
repr_out = "[" + ", ".join("'" + x.replace("'", "") + "'" for x in out) + "]"
subprocess.check_call(["gsettings", "set", schema, key, repr_out])
print("mate pins", repr_out)
PY
    fi
    log "MATE panel launchers"
    python3 - <<'PY' || true
import ast, subprocess
from pathlib import Path
wanted = [
  "brave-browser.desktop", "google-chrome.desktop", "firefox.desktop",
  "thunderbird.desktop", "org.keepassxc.KeePassXC.desktop",
  "libreoffice-writer.desktop",
]
for editor in ("xed.desktop", "pluma.desktop", "org.gnome.TextEditor.desktop"):
    if Path("/usr/share/applications", editor).is_file():
        wanted.append(editor)
        break
wanted += ["caja.desktop", "org.gnome.Calculator.desktop", "mate-terminal.desktop"]
def run(args):
    return subprocess.check_output(args, text=True).strip()
try:
    ids = ast.literal_eval(run(["gsettings", "get", "org.mate.panel", "object-id-list"]))
except Exception:
    print("no mate panel")
    raise SystemExit
if not isinstance(ids, list):
    ids = []
existing = set()
for oid in ids:
    loc = subprocess.run(["gsettings", "get", f"org.mate.panel.object:/org/mate/panel/objects/{oid}/", "launcher-location"], text=True, capture_output=True)
    if loc.returncode == 0:
        existing.add(loc.stdout.strip().strip("'"))
pos = 20
added = []
for name in wanted:
    desktop = f"/usr/share/applications/{name}"
    if not Path(desktop).is_file() or desktop in existing or name in existing:
        continue
    oid = f"readylinux-{name.replace('.desktop','')}"
    path = f"org.mate.panel.object:/org/mate/panel/objects/{oid}/"
    subprocess.check_call(["gsettings", "set", path, "object-type", "launcher"])
    subprocess.check_call(["gsettings", "set", path, "launcher-location", desktop])
    subprocess.check_call(["gsettings", "set", path, "toplevel-id", "bottom"])
    subprocess.check_call(["gsettings", "set", path, "position", str(pos)])
    subprocess.check_call(["gsettings", "set", path, "locked", "true"])
    ids.append(oid)
    added.append(name)
    pos += 20
if added:
    repr_ids = "[" + ", ".join("'" + x.replace("'", "") + "'" for x in ids) + "]"
    subprocess.check_call(["gsettings", "set", "org.mate.panel", "object-id-list", repr_ids])
    print("mate panel", added)
else:
    print("mate panel unchanged")
PY
    # Mint's bottom bar is 24px. 36 is readable without being tall.
    python3 - <<'PY' || true
import ast, subprocess
raw = subprocess.check_output(["gsettings", "get", "org.mate.panel", "toplevel-id-list"], text=True).strip()
try:
    ids = ast.literal_eval(raw)
except Exception:
    ids = ["bottom"]
for tid in ids:
    path = f"org.mate.panel.toplevel:/org/mate/panel/toplevels/{tid}/"
    subprocess.run(["gsettings", "set", path, "size", "40"], check=False)
    print("panel size", tid)
PY
    ;;
  *xfce*)
    log "Xfce Whisker favorites and left-side pins"
    # Skip apps already on the bar. Reset the list, do not append.
    # An expanding separator is what right-justifies the tray and clock.
    if command -v xfconf-query >/dev/null; then
      names=(brave-browser.desktop google-chrome.desktop firefox.desktop \
             thunderbird.desktop org.keepassxc.KeePassXC.desktop \
             libreoffice-writer.desktop xed.desktop org.gnome.TextEditor.desktop kolourpaint.desktop org.kde.kolourpaint.desktop \
             thunar.desktop org.gnome.Calculator.desktop xfce4-terminal.desktop)
      editor=""
      shopt -s nocaseglob
      for f in /usr/share/applications/xed.desktop /usr/share/applications/org.gnome.TextEditor.desktop /usr/share/applications/mousepad.desktop; do
        [[ -f "$f" ]] && { editor="$(basename "$f")"; break; }
      done
      shopt -u nocaseglob
      [[ -n "$editor" ]] && names+=("$editor")
      args=(-c xfce4-panel -p /plugins/plugin-1/favorites -n)
      for n in "${names[@]}"; do
        [[ -f "/usr/share/applications/$n" ]] && args+=(-t string -s "$n")
      done
      xfconf-query "${args[@]}" || true
      ids="$(xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids 2>/dev/null || true)"
      nums="$(echo "$ids" | grep -E '^[0-9]+$' | awk '!seen[$0]++' || true)"
      have=""
      for n in $nums; do
        item="$(xfconf-query -c xfce4-panel -p /plugins/plugin-"$n"/items 2>/dev/null | grep -E '\.desktop$' | head -n1 || true)"
        [[ -n "$item" ]] && have="$have $item"
      done
      next=40
      new=()
      for name in "${names[@]}"; do
        src="/usr/share/applications/$name"
        [[ -f "$src" ]] || continue
        [[ "$have" == *" $name"* ]] && continue
        while echo "$nums" | grep -qx "$next"; do next=$((next + 1)); done
        mkdir -p "$HOME/.config/xfce4/panel/launcher-$next"
        cp -f "$src" "$HOME/.config/xfce4/panel/launcher-$next/$name"
        xfconf-query -c xfce4-panel -p "/plugins/plugin-$next" -n -t string -s launcher || true
        xfconf-query -c xfce4-panel -p "/plugins/plugin-$next/items" -r 2>/dev/null || true
        xfconf-query -c xfce4-panel -p "/plugins/plugin-$next/items" -n -t string -s "$name" || true
        new+=("$next")
        nums="$nums"$'\n'"$next"
        next=$((next + 1))
      done
      left=()
      system=()
      sep=""
      seen_items=" "
      for n in $nums; do
        [[ " ${new[*]} " == *" $n "* ]] && continue
        kind="$(xfconf-query -c xfce4-panel -p /plugins/plugin-"$n" 2>/dev/null || true)"
        item="$(xfconf-query -c xfce4-panel -p /plugins/plugin-"$n"/items 2>/dev/null | grep -E '\.desktop$' | head -n1 || true)"
        if [[ -n "$item" && "$seen_items" == *" $item "* ]]; then
          continue
        fi
        [[ -n "$item" ]] && seen_items="$seen_items$item "
        if [[ "$item" == *xed* || "$item" == *TextEditor* || "$item" == *mousepad* || "$item" == *text-editor* ]]; then
          left+=("$n")
          continue
        fi
        case "$kind" in
          systray|notification-plugin|xapp-status-plugin|power-manager-plugin|pulseaudio|clock)
            xfconf-query -c xfce4-panel -p "/plugins/plugin-$n/items" -r 2>/dev/null || true
            system+=("$n")
            ;;
          separator)
            [[ -z "$sep" ]] && sep="$n"
            ;;
          *)
            left+=("$n")
            ;;
        esac
      done
      if [[ -z "$sep" ]]; then
        sep="$next"
        xfconf-query -c xfce4-panel -p "/plugins/plugin-$sep" -n -t string -s separator || true
      fi
      xfconf-query -c xfce4-panel -p "/plugins/plugin-$sep/expand" -n -t bool -s true || true
      xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids -r || true
      args=(-c xfce4-panel -p /panels/panel-1/plugin-ids -n)
      for n in "${left[@]}" "${new[@]}" "$sep" "${system[@]}"; do
        [[ -n "$n" ]] && args+=(-t int -s "$n")
      done
      xfconf-query "${args[@]}" || true
      xfce4-panel -r || true
      xfconf-query -c xfce4-panel -p /panels/panel-1/size -n -t int -s 40 || true
      xfconf-query -c xfce4-panel -p /panels/panel-1/icon-size -n -t int -s 40 || true
    fi
    sudo apt-get install -y wmctrl xdotool || true
    if gsettings list-schemas | grep -qx 'org.gnome.TextEditor'; then
      gsettings set org.gnome.TextEditor use-system-font false || true
      gsettings set org.gnome.TextEditor custom-font 'Monospace 12' || true
      echo "text editor font $(gsettings get org.gnome.TextEditor custom-font 2>/dev/null || echo failed)"
    else
      echo "no text editor schema"
    fi
    # Xed remembers a maximized 1920x1003 window. 0 is not maximized.
    if gsettings list-schemas | grep -qx 'org.x.editor.state.window'; then
      gsettings set org.x.editor.state.window size "(1100, 700)" || true
      gsettings set org.x.editor.state.window state 0 || true
    fi
    if command -v xfconf-query >/dev/null; then
      xfconf-query -c thunar -p /last-window-width -n -t int -s 1100 2>/dev/null || true
      xfconf-query -c thunar -p /last-window-height -n -t int -s 700 2>/dev/null || true
      xfconf-query -c thunar -p /last-window-maximized -n -t bool -s false 2>/dev/null || true
    fi
    # Thunar does not remember position. The menu launcher moves it after open.
    if command -v wmctrl >/dev/null && command -v xdotool >/dev/null; then
      mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
      cat > "$HOME/.local/bin/thunar-place" <<'EOF'
#!/usr/bin/env bash
/usr/bin/thunar "$@" &
sleep 0.6
hex="$(wmctrl -l | grep -i thunar | awk '{print $1; exit}')"
[[ -n "${hex:-}" ]] || exit 0
dec=$((hex))
wmctrl -i -r "$hex" -b remove,maximized_vert,maximized_horz
xdotool windowmove "$dec" 40 40
xdotool windowsize "$dec" 1100 700
EOF
      chmod +x "$HOME/.local/bin/thunar-place"
      cat > "$HOME/.local/share/applications/thunar.desktop" <<EOF
[Desktop Entry]
Name=Thunar
Exec=$HOME/.local/bin/thunar-place %F
Icon=thunar
Terminal=false
Type=Application
Categories=System;FileManager;
MimeType=inode/directory;
EOF
    fi
    ;;
  *zorin*)
    log "Zorin pins only. Panel layout is left as Zorin set it."
    pin_gnome org.gnome.shell org.gnome.Nautilus.desktop org.gnome.TextEditor.desktop || true
    ;;
  *kde*|*plasma*)
    log "KDE places. Panel pins are not the Ubuntu dock, so they are left as they are."
    xbel="$HOME/.local/share/user-places.xbel"
    mkdir -p "$HOME/.local/share"
    if [[ ! -f "$xbel" ]]; then
      printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<xbel version="1.0">' '</xbel>' > "$xbel"
    fi
    for pair in "$HOME/Media|Media" "$HOME/Documents/AppFiles|AppFiles"; do
      uri="file://${pair%%|*}"
      label="${pair##*|}"
      grep -qF "$uri" "$xbel" || sed -i "s#</xbel># <bookmark href=\"$uri\"><title>$label</title></bookmark>\n</xbel>#" "$xbel"
    done
    ;;
  *)
    pin_gnome org.gnome.shell org.gnome.Nautilus.desktop org.gnome.TextEditor.desktop || true
    if gsettings list-schemas | grep -q 'org.gnome.shell.extensions.dash-to-dock'; then
      gnome-extensions enable dash-to-dock@micxgx.gmail.com 2>/dev/null || true
      pos="$(gsettings get org.gnome.shell.extensions.dash-to-dock dock-position 2>/dev/null || echo '')"
      if [[ "$pos" == "'LEFT'" ]]; then
        gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM' || true
        gsettings set org.gnome.shell.extensions.dash-to-dock extend-height false || true
      fi
      gsettings set org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 40 || true
    fi
    ;;
esac
fi

if [[ "${CHANGE_APPLY[lid]}" == "1" ]] && gsettings list-keys org.gnome.settings-daemon.plugins.power 2>/dev/null | grep -q lid-close-ac-action; then
  gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action 'nothing' || true
  gsettings set org.gnome.settings-daemon.plugins.power lid-close-battery-action 'suspend' || true
fi

# Files remembers a maximized window. Open it at a normal size.
if [[ "${CHANGE_APPLY[filemanager]}" == "1" ]] && gsettings list-schemas | grep -qx 'org.gnome.nautilus.window-state'; then
  gsettings set org.gnome.nautilus.window-state maximized false || true
  gsettings set org.gnome.nautilus.window-state initial-size '(1100, 700)' || true
fi
if [[ "${CHANGE_APPLY[editorlook]}" == "1" ]] && gsettings list-schemas | grep -qx 'org.gnome.TextEditor'; then
  gsettings set org.gnome.TextEditor style-scheme 'classic' || true
  gsettings set org.gnome.TextEditor use-system-font false || true
  gsettings set org.gnome.TextEditor custom-font 'Monospace 12' || true
elif gsettings list-schemas | grep -qx 'org.gnome.gedit.preferences.editor'; then
  gsettings set org.gnome.gedit.preferences.editor scheme 'classic' || true
  gsettings set org.gnome.gedit.preferences.editor use-default-font false || true
  gsettings set org.gnome.gedit.preferences.editor editor-font 'Monospace 12' || true
fi
if [[ "${CHANGE_APPLY[editorlook]}" == "1" ]]; then
python3 - <<'PY' || true
from pathlib import Path
try:
    from gi.repository import GLib
except Exception:
    raise SystemExit(0)
path = Path.home() / ".local/share/org.gnome.TextEditor/session.gvariant"
if not path.is_file():
    raise SystemExit(0)
data = GLib.Bytes.new(path.read_bytes())
variant = GLib.Variant.new_from_bytes(GLib.VariantType.new("a{sv}"), data, False)
items = []
for i in range(variant.n_children()):
    entry = variant.get_child_value(i)
    key = entry.get_child_value(0).get_string()
    if key == "default-window-size":
        items.append((key, GLib.Variant("(uu)", (1100, 700))))
    else:
        items.append((key, entry.get_child_value(1).get_variant()))
new = GLib.Variant("a{sv}", items)
path.write_bytes(bytes(new.get_data_as_bytes().get_data()))
print("text editor window 1100x700")
PY
if gsettings list-schemas | grep -qx 'org.x.editor.preferences.editor'; then
  gsettings set org.x.editor.preferences.editor use-default-font false || true
  gsettings set org.x.editor.preferences.editor editor-font 'Monospace 12' || true
fi
fi

# Terminal frame is 110x34 on the distros we support.
# Newer Ubuntu uses Ptyxis. Zorin and Mint use GNOME Terminal.
if [[ "${CHANGE_APPLY[terminal]}" == "1" ]]; then
if gsettings list-schemas | grep -qx 'org.gnome.Ptyxis'; then
  gsettings set org.gnome.Ptyxis default-columns 110 || true
  gsettings set org.gnome.Ptyxis default-rows 34 || true
  gsettings set org.gnome.Ptyxis use-system-font false || true
  gsettings set org.gnome.Ptyxis font-name 'Monospace 10' || true
fi
if gsettings list-schemas | grep -qx 'org.gnome.Terminal.Legacy.Settings' && command -v gnome-terminal >/dev/null; then
  python3 - <<'PY' || true
import subprocess
def setv(path, key, val):
    subprocess.check_call(["gsettings", "set", path, key, val])
raw = subprocess.check_output(["dconf", "list", "/org/gnome/terminal/legacy/profiles:/"], text=True)
uids = [line.strip("/:") for line in raw.splitlines() if line.strip()]
default = ""
if "default" in subprocess.check_output(["gsettings", "list-keys", "org.gnome.Terminal.Legacy.Settings"], text=True).split():
    default = subprocess.check_output(["gsettings", "get", "org.gnome.Terminal.Legacy.Settings", "default"], text=True).strip().strip("'")
if default and default not in uids:
    uids.append(default)
if not uids:
    print("gnome-terminal has no profile yet; size applies after the first terminal is closed and opened")
for uid in uids:
    path = f"org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:{uid}/"
    setv(path, "default-size-columns", "110")
    setv(path, "default-size-rows", "34")
    setv(path, "use-system-font", "false")
    setv(path, "font", "'Monospace 10'")
    setv(path, "use-theme-colors", "false")
    setv(path, "foreground-color", "'#FFFFFF'")
    setv(path, "background-color", "'#000000'")
    print("gnome-terminal next window 110x34", uid)
PY
  mkdir -p "$HOME/.local/share/applications"
  cat > "$HOME/.local/share/applications/org.gnome.Terminal.desktop" <<EOF
[Desktop Entry]
Name=Terminal
Exec=gnome-terminal --geometry=110x34
Icon=org.gnome.Terminal
Terminal=false
Type=Application
Categories=System;TerminalEmulator;
StartupNotify=true
EOF
fi
# Xfce Terminal ignores the GNOME geometry. 110x34, 10pt, black on white.
if [[ -d /usr/share/xfce4/terminal || -f /usr/bin/xfce4-terminal ]]; then
  mkdir -p "$HOME/.config/xfce4/terminal"
  termrc="$HOME/.config/xfce4/terminal/terminalrc"
  touch "$termrc"
  grep -q '^\[Configuration\]' "$termrc" || printf '\n[Configuration]\n' >> "$termrc"
  for kv in "MiscDefaultGeometry=120x36" "FontName=Monospace 10" "ColorForeground=#ffffff" "ColorBackground=#000000"; do
    key="${kv%%=*}"
    sed -i "/^${key}=/d" "$termrc"
    printf '%s\n' "$kv" >> "$termrc"
  done
fi
fi

if [[ "${CHANGE_APPLY[scale]}" == "1" ]]; then
# 125% on a laptop or a 1080p-class screen. A desktop at 1440p or 4K stays at 100%.
primary_w="$(xrandr 2>/dev/null | awk '/ connected/{print $3; exit}' | cut -dx -f1)"
if [[ -d /sys/class/power_supply ]] && compgen -G /sys/class/power_supply/BAT* >/dev/null; then
  SCALE="1.25"
elif [[ -n "${primary_w:-}" && "$primary_w" -le 1920 ]]; then
  SCALE="1.25"
else
  SCALE="1.0"
fi
log "Screen scale $SCALE"
if gsettings writable org.gnome.desktop.interface text-scaling-factor >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface text-scaling-factor "$SCALE" || true
fi
if gsettings writable org.cinnamon.desktop.interface text-scaling-factor >/dev/null 2>&1; then
  gsettings set org.cinnamon.desktop.interface text-scaling-factor "$SCALE" || true
fi
if gsettings writable org.cinnamon active-display-scale >/dev/null 2>&1; then
  gsettings set org.cinnamon active-display-scale "$SCALE" || true
fi
# MATE has no 125% display scale. 120 DPI is the same size change.
if [[ "$SCALE" == "1.25" ]] && gsettings writable org.mate.font-rendering dpi >/dev/null 2>&1; then
  gsettings set org.mate.font-rendering dpi 120 || true
fi
# Xfce uses DPI, not the GNOME scale key. 120 is the 125% size.
if [[ "$SCALE" == "1.25" ]] && command -v xfconf-query >/dev/null; then
  xfconf-query -c xsettings -p /Xft/DPI -n -t int -s 120 2>/dev/null || \
    xfconf-query -c xsettings -p /Xft/DPI -t int -s 120 2>/dev/null || true
fi
if [[ "$SCALE" == "1.25" && -f "$HOME/.config/cinnamon-monitors.xml" ]]; then
  sed -i 's/scale="0.75"/scale="1.25"/g; s/<scale>0.75<\/scale>/<scale>1.25<\/scale>/g' \
    "$HOME/.config/cinnamon-monitors.xml" || true
fi
fi

if [[ "${CHANGE_APPLY[wallpaper]}" == "1" ]]; then
if [[ -n "$WALLPAPER_URL" ]]; then
  mkdir -p "$HOME/.local/share/backgrounds"
  wall="$HOME/.local/share/backgrounds/human-linux-wallpaper.jpg"
  if gsettings list-schemas | grep -qx 'org.mate.background'; then
    current="$(gsettings get org.mate.background picture-filename 2>/dev/null || echo '')"
    if [[ "$current" == *"/usr/share/backgrounds/"* || "$current" == "''" ]]; then
      if curl -fsSL -o "$wall" "$WALLPAPER_URL"; then
        gsettings set org.mate.background picture-filename "$wall" || true
        gsettings set org.mate.background picture-options 'zoom' || true
      else
        warn "Wallpaper download failed"
      fi
    else
      log "Wallpaper already chosen. Skipped."
    fi
  else
    current="$(gsettings get org.gnome.desktop.background picture-uri 2>/dev/null || echo '')"
    dark="$(gsettings get org.gnome.desktop.background picture-uri-dark 2>/dev/null || echo '')"
    if [[ "$current" == *"human-linux-wallpaper.jpg"* && "$dark" == *"human-linux-wallpaper.jpg"* ]]; then
      log "Wallpaper already set."
    elif curl -fsSL -o "$wall" "$WALLPAPER_URL"; then
      gsettings set org.gnome.desktop.background picture-uri "file://$wall" || true
      gsettings set org.gnome.desktop.background picture-uri-dark "file://$wall" || true
      gsettings set org.gnome.desktop.background picture-options 'zoom' || true
    else
      warn "Wallpaper download failed"
    fi
  fi
else
  log "Wallpaper URL blank. Skipped."
fi
# Xfce wallpaper is per monitor. The live laptop panel is monitoreDP-1.
# last-image alone does not change the picture while cycling is on.
if [[ -n "$WALLPAPER_URL" ]] && command -v xfconf-query >/dev/null && [[ "$de" == *xfce* ]]; then
  mkdir -p "$HOME/.local/share/backgrounds"
  wall="$HOME/.local/share/backgrounds/human-linux-wallpaper.jpg"
  if curl -fsSL -o "$wall" "$WALLPAPER_URL"; then
    for prop in \
      /backdrop/screen0/monitoreDP-1/workspace0/last-image \
      /backdrop/screen0/monitoreDP-1/workspace0/image-path \
      /backdrop/screen0/monitor0/image-path \
      /backdrop/screen0/monitor0/last-single-image
    do
      xfconf-query -c xfce4-desktop -p "$prop" -n -t string -s "$wall" 2>/dev/null || true
    done
    xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitoreDP-1/workspace0/backdrop-cycle-enable -n -t bool -s false 2>/dev/null || true
  fi
fi
fi

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

if [[ "${CHANGE_APPLY[shelltools]}" == "1" ]]; then
# Click a .sh in Files: Run or Edit, instead of opening the text editor.
log "Script launcher"
cat > "$HOME/.local/bin/sh-launcher" <<'EOF'
#!/usr/bin/env bash
f="${1:-}"
[[ -n "$f" && -f "$f" ]] || { zenity --error --text="No script given."; exit 1; }
zenity --question --width=420 --title="Script" \
  --ok-label="Run" --cancel-label="Edit" \
  --text="File: $f

Run starts this script.
Edit opens it in the text editor." || {
  if command -v gnome-text-editor >/dev/null; then exec gnome-text-editor "$f"
  elif command -v gedit >/dev/null; then exec gedit "$f"
  elif command -v xed >/dev/null; then exec xed "$f"
  elif command -v pluma >/dev/null; then exec pluma "$f"
  elif command -v mousepad >/dev/null; then exec mousepad "$f"
  else zenity --error --text="No text editor found."
  fi
  exit 0
}
chmod +x "$f" || true
if command -v gnome-terminal >/dev/null; then
  gnome-terminal -- bash -c "bash \"$f\"; echo; read -r -p 'Press Enter to close.'"
elif command -v kgx >/dev/null; then
  kgx -- bash -c "bash \"$f\"; echo; read -r -p 'Press Enter to close.'"
elif command -v x-terminal-emulator >/dev/null; then
  x-terminal-emulator -e bash -c "bash \"$f\"; echo; read -r -p 'Press Enter to close.'"
else
  zenity --error --text="No terminal program found."
fi
EOF
chmod +x "$HOME/.local/bin/sh-launcher"
cat > "$HOME/.local/share/applications/sh-launcher.desktop" <<EOF
[Desktop Entry]
Name=Script launcher
Exec=$HOME/.local/bin/sh-launcher %f
Terminal=false
Type=Application
MimeType=text/x-shellscript;application/x-shellscript;
NoDisplay=true
X-ReadyLinux=true
EOF
xdg-mime default sh-launcher.desktop text/x-shellscript || true
xdg-mime default sh-launcher.desktop application/x-shellscript || true
# Nemo asks Run or Display before the default app. Launch skips that and opens ours.
if gsettings writable org.nemo.preferences executable-text-activation >/dev/null 2>&1; then
  gsettings set org.nemo.preferences executable-text-activation 'launch' || true
fi

# Clickable launchers. Files will not run a .sh; these .desktop files do.
if [[ -f "$0" ]]; then
  kit="$HOME/.local/share/human-linux"
  mkdir -p "$kit" "$HOME/.local/share/applications"
  cp -f "$0" "$kit/install.sh"
  chmod +x "$kit/install.sh"
  if [[ -f "$(dirname "$0")/uninstall.sh" ]]; then
    cp -f "$(dirname "$0")/uninstall.sh" "$kit/uninstall.sh"
    chmod +x "$kit/uninstall.sh"
  fi
  cat > "$HOME/.local/share/applications/human-linux-install.desktop" <<EOF
[Desktop Entry]
Name=ReadyLinux install
Comment=Preview, confirm, then run the install
Exec=$kit/install.sh
Terminal=false
Type=Application
Icon=system-software-install
Categories=Utility;
EOF
  cat > "$HOME/.local/share/applications/human-linux-uninstall.desktop" <<EOF
[Desktop Entry]
Name=ReadyLinux uninstall
Comment=Preview, confirm, then remove kit files
Exec=$kit/uninstall.sh
Terminal=false
Type=Application
Icon=user-trash
Categories=Utility;
EOF
  chmod +x "$HOME/.local/share/applications/human-linux-install.desktop" \
           "$HOME/.local/share/applications/human-linux-uninstall.desktop" || true
  gio set "$HOME/.local/share/applications/human-linux-install.desktop" metadata::trusted true 2>/dev/null || true
  gio set "$HOME/.local/share/applications/human-linux-uninstall.desktop" metadata::trusted true 2>/dev/null || true
fi
fi

log "Done."
echo "Plug a USB stick in. It should appear under ~/Media/Disks after Ubuntu mounts it."
echo "Show Apps: ReadyLinux install, and ReadyLinux uninstall."
echo "Log out and back in if Show Apps or the dock did not update."
echo "On Zorin, dock icons can show but not click until that logout."
echo "Lid-on-AC applies fully after the next reboot. logind was not restarted."
