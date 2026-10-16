<div align="center">
  <img src="images/logos/archlinux.svg" alt="Arch Linux" height="48">
  &nbsp;&nbsp;
  <img src="images/logos/niri.svg" alt="niri" height="48">
  &nbsp;&nbsp;
  <img src="images/logos/quickshell.svg" alt="Quickshell" height="48">

  <h2>Arkaizn's Dotfiles</h2>

  <p>niri + Quickshell on Arch Linux, with a pywal theme that follows the wallpaper.<br>
  Includes an installer that turns a fresh Arch install into this setup.</p>
</div>

## Screenshots

<table>
  <tr>
    <td align="center"><a href="images/01-desktop.png"><img src="images/01-desktop.png" alt="Desktop"></a><br><sub><b>Desktop</b>: bar, fastfetch, btop</sub></td>
    <td align="center"><a href="images/02-launcher.png"><img src="images/02-launcher.png" alt="Launcher"></a><br><sub><b>Launcher</b>: frecency-ranked apps, Tab for clipboard / wallpapers</sub></td>
    <td align="center"><a href="images/03-wallpapers.png"><img src="images/03-wallpapers.png" alt="Wallpaper picker"></a><br><sub><b>Wallpapers</b>: picking one re-themes everything</sub></td>
  </tr>
  <tr>
    <td align="center"><a href="images/04-dashboard.png"><img src="images/04-dashboard.png" alt="Dashboard"></a><br><sub><b>Dashboard</b>: profile, music, calendar, system stats</sub></td>
    <td align="center"><a href="images/05-controlcenter.png"><img src="images/05-controlcenter.png" alt="Control center"></a><br><sub><b>Control center</b>: power, Wi-Fi, BT, tools, mixer</sub></td>
    <td align="center"><a href="images/06-traymenu.png"><img src="images/06-traymenu.png" alt="Tray menu"></a><br><sub><b>Tray menu</b>: themed menus from the bar</sub></td>
  </tr>
  <tr>
    <td align="center"><a href="images/07-notification.png"><img src="images/07-notification.png" alt="Notification"></a><br><sub><b>Notifications</b>: popups top right</sub></td>
    <td align="center"><a href="images/08-lockscreen.png"><img src="images/08-lockscreen.png" alt="Lockscreen"></a><br><sub><b>Lockscreen</b>: clock, media, notifications</sub></td>
    <td align="center"><a href="images/09-lockscreen-auth.png"><img src="images/09-lockscreen-auth.png" alt="Lockscreen password"></a><br><sub><b>Unlock</b>: password or YubiKey</sub></td>
  </tr>
</table>

## Installation

Start from a fresh Arch Linux install:

```sh
git clone https://gitlab.silnas.ch/arkaizn/Dotfiles && cd Dotfiles
./install.sh        # packages, configs, themes
./postinstall.sh    # optional: apps, zsh, nvidia, openrgb, greetd
```

## Timeline

Each version is a git tag. Expand a version to see its screenshots.

| Version | Date | Setup |
|---|---|---|
| **current** | 2026-06 → | niri + Quickshell (screenshots above) |
| [`v0.3`](../../tree/v0.3) | 2026-04 | Hyprland + Quickshell redesign |
| [`v0.2`](../../tree/v0.2) | 2025-11 | Hyprland + early Quickshell |
| [`v0.1`](../../tree/v0.1) | 2025-09 | Hyprland + Waybar + swaync |
| [`v0.0`](../../tree/v0.0) | 2024-10 | Gnome |

<details>
<summary><b>v0.3</b>: Hyprland + Quickshell redesign</summary>
<br>
<table>
  <tr>
    <td><a href="images/history/v0.3-hyprland-quickshell/fastfetch-eva.png"><img src="images/history/v0.3-hyprland-quickshell/fastfetch-eva.png" alt="v0.3 fastfetch"></a></td>
    <td><a href="images/history/v0.3-hyprland-quickshell/browser-purple.png"><img src="images/history/v0.3-hyprland-quickshell/browser-purple.png" alt="v0.3 browser"></a></td>
    <td><a href="images/history/v0.3-hyprland-quickshell/fastfetch-fuji.png"><img src="images/history/v0.3-hyprland-quickshell/fastfetch-fuji.png" alt="v0.3 fastfetch"></a></td>
  </tr>
  <tr>
    <td><a href="images/history/v0.3-hyprland-quickshell/browser-dark.png"><img src="images/history/v0.3-hyprland-quickshell/browser-dark.png" alt="v0.3 browser"></a></td>
    <td><a href="images/history/v0.3-hyprland-quickshell/notifications-space.png"><img src="images/history/v0.3-hyprland-quickshell/notifications-space.png" alt="v0.3 notifications"></a></td>
    <td><a href="images/history/v0.3-hyprland-quickshell/browser-blue.png"><img src="images/history/v0.3-hyprland-quickshell/browser-blue.png" alt="v0.3 browser"></a></td>
  </tr>
</table>
</details>

<details>
<summary><b>v0.2</b>: Hyprland + early Quickshell (no screenshots)</summary>
</details>

<details>
<summary><b>v0.1</b>: Hyprland + Waybar + swaync</summary>
<br>
<table>
  <tr>
    <td><a href="images/history/v0.1-hyprland-waybar/fastfetch-kaneki.png"><img src="images/history/v0.1-hyprland-waybar/fastfetch-kaneki.png" alt="v0.1 fastfetch"></a></td>
    <td><a href="images/history/v0.1-hyprland-waybar/browser-brown.png"><img src="images/history/v0.1-hyprland-waybar/browser-brown.png" alt="v0.1 browser"></a></td>
    <td><a href="images/history/v0.1-hyprland-waybar/swaync-brown.png"><img src="images/history/v0.1-hyprland-waybar/swaync-brown.png" alt="v0.1 swaync"></a></td>
  </tr>
  <tr>
    <td><a href="images/history/v0.1-hyprland-waybar/fastfetch-eva.png"><img src="images/history/v0.1-hyprland-waybar/fastfetch-eva.png" alt="v0.1 fastfetch"></a></td>
    <td><a href="images/history/v0.1-hyprland-waybar/browser-red.png"><img src="images/history/v0.1-hyprland-waybar/browser-red.png" alt="v0.1 browser"></a></td>
    <td><a href="images/history/v0.1-hyprland-waybar/swaync-red.png"><img src="images/history/v0.1-hyprland-waybar/swaync-red.png" alt="v0.1 swaync"></a></td>
  </tr>
</table>
</details>

<details>
<summary><b>v0.0</b>: Gnome (no screenshots)</summary>
</details>

## License

GPL-3.0. See [LICENSE](LICENSE).
