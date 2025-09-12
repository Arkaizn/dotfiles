<!-- Improved compatibility of back to top link: See: https://github.com/othneildrew/Best-README-Template/pull/73 -->
<a id="readme-top"></a>

<!-- PROJECT SHIELDS -->
[![Unlicense License][license-shield]][license-url]

<!-- PROJECT LOGO -->
<br />
<div align="center">
  <a href="https://github.com/arkaizn/Dotfiles">
    <img src="images\archlinux-logo.svg" alt="Logo" width="600" height="300">
  </a>

  <h3 align="center">Arch Linux Setup Scripts</h3>

  <p align="center">
    Automate your Arch Linux installation with a fully configured GUI and system settings.
    <br />
    <a href="https://github.com/arkaizn/Dotfiles"><strong>Explore the repository »</strong></a>
    <br />
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
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#why-this-project">Why This Project</a></li>
        <li><a href="#built-with">Built With</a></li>
      </ul>
    </li>
    <li><a href="#getting-started">Getting Started</a>
     <ul>
        <li><a href="#high-priority">High Priority</a></li>
        <li><a href="#low-priority">Low Priority</a></li>
     </ul>
    </li>
    <li><a href="#usage">Usage</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#project-structure">Project Structure</a></li>
    <li><a href="#home-manager">Home Manager</a></li>
    <li><a href="#license">License</a></li>
  </ol>
</details>

<!-- ABOUT THE PROJECT -->
## About The Project  

This project provides a collection of scripts to automate the installation and configuration of Arch Linux. It transforms a base Arch installation into a fully functional system with a graphical user interface (GUI) and essential configurations, making it ready for daily use.  

### Why This Project?  
- **Time-Saving** – Automates the tedious post-installation setup.  
- **Consistency** – Ensures a uniform configuration across multiple installations.  
- **Customization** – Easily adjustable to match your personal preferences.  

<p align="right">(<a href="#readme-top">Back to top</a>)</p>  

### Built With  

This project is powered by the following technologies:  

* [![Shell Script][ShellScript]][ShellScript-url]  
* [![CSS][CSS3]][CSS3-url]  
* [![JSONC][JSONC]][JSONC-url]  

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- GETTING STARTED -->
## Getting Started

To get started with this project, follow these simple steps.

### Prerequisites

- A fresh installation of Arch Linux.
- Basic knowledge of Linux commands.

### Installation

1. Clone the repository:
   ```sh
   git clone https://github.com/arkaizn/Dotfiles
   cd Dotfiles
   ```

2. Run the installation script:
   ```sh
   ./install.sh
   ```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- USAGE -->
## Usage

After running the installation script, your system will be fully configured with a GUI and all necessary settings. Below are some screenshots of the setup:

<!-- Screenshots  -->
![Screenshot 1](images/screenshot1.png)
![Screenshot 2](images/screenshot2.png)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- ROADMAP -->
## Roadmap

Here are some planned features and improvements for the project:

### High Priority
- [ ] **Add Images of the System**
- [ ] **make a better insatllation script with gum**

### Low Priority
- [ ] **Configure Hyprland plugins**.
- [ ] **Clean up scripts (structure)**:
  - Refactor and organize script files for better structure and readability.
- [ ] **Text from image**:
  - Implement OCR functionality to extract text from images.

### Done
- [x] **Basic system setup and GUI installation.**
- [x] **Configured**
  - hyprland, waybar, hyprlock, wofi, pywal, fastfetch, swaync
- [x] **Configure TUI (pre-installation) and GUI (post-installation) for the scripts**.
- [x] **Fix theme and icon not working**
- [x] **Replace Theme and Icon Folders with an intallation**
- [x] **Create nvidia.sh script**:
  - Automate setup for NVIDIA drivers and configurations (Grub, etc.).

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- Project Structure -->
## Project Structure

```
    dotfiles/
    ├── .config/
    │   └── hypr/
    │       ├── hyprland.conf
    │       └── ...
    ├── additions/
    │   ├── apps.sh
    │   ├── openrgb/
    │   │   └── openrgb.sh
    │   └── nvidia.sh
    ├── images/
    │   └── ...
    ├── scripts/
    │   ├── config.sh
    │   ├── icons.sh
    │   ├── packages.sh
    │   ├── theme.sh
    │   └── zshinstall.sh
    ├── LICENSE
    ├── README.md
    ├── install.sh
    ├── postinstall.sh
    └── refresh.sh
```
<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- LICENSE -->
## License

This project is licensed under the Unlicense. See [LICENSE](https://github.com/arkaizn/Dotfiles/blob/master/LICENSE) for more details.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- MARKDOWN LINKS & IMAGES -->
[license-shield]: https://img.shields.io/badge/license-Unlicense-blue.svg?style=for-the-badge
[license-url]: https://github.com/arkaizn/Dotfiles/blob/master/LICENSE

[ShellScript]: https://img.shields.io/badge/Shell_Script-%23121011.svg?style=for-the-badge&logo=gnu-bash&logoColor=white  
[ShellScript-url]: https://www.gnu.org/software/bash/  

[CSS3]: https://img.shields.io/badge/CSS3-%231572B6.svg?style=for-the-badge&logo=css3&logoColor=white  
[CSS3-url]: https://developer.mozilla.org/en-US/docs/Web/CSS  

[JSONC]: https://img.shields.io/badge/JSONC-%23000000.svg?style=for-the-badge&logo=json&logoColor=white  
[JSONC-url]: https://code.visualstudio.com/docs/languages/json  

