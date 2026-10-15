<!-- Improved compatibility of back to top link: See: https://gitlab.silnas.ch/othneildrew/Best-README-Template/pull/73 -->
<a id="readme-top"></a>

<!-- PROJECT SHIELDS -->
[![License][license-shield]][license-url]
 
<!-- PROJECT LOGO -->
<br />
<div align="center">
  <a href="https://gitlab.silnas.ch/arkaizn/dotfiles">
    <img src="images\archlinux-logo.svg" alt="Logo" width="600" height="300">
  </a>

  <h3 align="center">Arch Linux Setup Scripts</h3>

  <p align="center">
    Automate your Arch Linux installation with a fully configured GUI and system settings.
    <br />
    <a href="https://github.com/arkaizn/Dotfiles/issues/new?labels=bug&template=bug-report---.md">Report Bug</a>
    ·
    <a href="https://github.com/arkaizn/Dotfiles/issues/new?labels=enhancement&template=feature-request---.md">Request Feature</a>
  </p>
</div>

<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li><a href="#about-the-project">About The Project</a></li>
    <li><a href="#getting-started">Getting Started</a></li>
    <li><a href="#Screenshots">Screenshots</a></li>
    <li><a href="#project-structure">Project Structure</a></li>
    <li><a href="#license">License</a></li>
  </ol>
</details>

<!-- ABOUT THE PROJECT -->
## About The Project  

This project provides a collection of scripts to automate the installation and configuration of Arch Linux. It transforms a base Arch installation into a fully functional system with a graphical user interface (GUI) and essential configurations, making it ready for daily use.  

<!-- GETTING STARTED -->
## Getting Started

To get started with this project, follow these simple steps.

### Prerequisites

- A fresh installation of Arch Linux.
- Basic knowledge of Linux commands.

### Installation

1. Clone the repository:
   ```sh
   git clone https://gitlab.silnas.ch/arkaizn/Dotfiles
   cd Dotfiles
   ```

2. Run the installation script:
   ```sh
   ./install.sh
   ```

3. (Optional) Install the extras (apps, zsh, nvidia, openrgb, greetd):
   ```sh
   ./postinstall.sh
   ```

## Screenshots
<!-- Screenshots  -->
niri + Quickshell. Older screenshots live in [`images/archive/`](images/archive/).

**Desktop** — bar, fastfetch and btop on a fresh workspace
![Desktop](images/01-desktop.png)

**Launcher** — app search with frecency-ranked recommendations (Tab switches to clipboard / wallpapers)
![Launcher](images/02-launcher.png)

**Wallpaper picker** — inside the launcher; picking one re-themes everything with pywal
![Wallpaper picker](images/03-wallpapers.png)

**Dashboard** — profile, music player, calendar and system stats
![Dashboard](images/04-dashboard.png)

**Control center** — power, Wi-Fi, Bluetooth, screenshot / OCR / color picker, volume mixer, notifications
![Control center](images/05-controlcenter.png)

**Tray menu** — themed tray menus hanging from the bar
![Tray menu](images/06-traymenu.png)

**Notifications** — popups slide in from the top right
![Notification](images/07-notification.png)

**Lockscreen** — clock, media and notifications; any key opens the password prompt
![Lockscreen](images/08-lockscreen.png)
![Lockscreen password](images/09-lockscreen-auth.png)

<!-- Project Structure -->
## Project Structure

```
    dotfiles/
    ├── .config/
    │   └── hypr/
    │       ├── hyprland.conf
    │       └── ...
    ├── additions/              # misc scripts & notes (not run by the installers)
    ├── images/                 # README screenshots
    │   └── archive/            # older screenshots
    ├── scripts/
    │   ├── lib.sh              # shared gum helpers
    │   ├── install/            # steps run by install.sh
    │   │   ├── packages.sh
    │   │   ├── config.sh
    │   │   └── themes.sh
    │   ├── postinstall/        # steps run by postinstall.sh
    │   │   ├── apps.sh
    │   │   ├── zsh.sh
    │   │   ├── nvidia.sh
    │   │   ├── greetd.sh
    │   │   └── openrgb/
    │   └── config/             # pull / push / update dotfiles
    ├── LICENSE
    ├── README.md
    ├── install.sh
    └── postinstall.sh
```

<!-- LICENSE -->
## License

This project is licensed under the GNU License. See [LICENSE](https://gitlab.silnas.ch/arkaizn/dotfiles/-/blob/main/LICENSE) for more details.

<!-- MARKDOWN LINKS & IMAGES -->
[license-shield]: https://img.shields.io/github/license/arkaizn/dotfiles
[license-url]: https://gitlab.silnas.ch/arkaizn/dotfiles/-/blob/main/LICENSE

