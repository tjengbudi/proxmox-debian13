[![Version](https://img.shields.io/badge/Version-1.1.0-red.svg)](version) [![License](https://img.shields.io/badge/License-BSD--Clause_3-green.svg)](LICENSE)

```bash
                                                                  _
             _ __  _ __ _____  ___ __ ___   _____  __    ___  ___| |_ _   _ _ __
            | '_ \| '__/ _ \ \/ / '_ ` _ \ / _ \ \/ /   / __|/ _ \ __| | | | '_ \
            | |_) | | | (_) >  <| | | | | | (_) >  <    \__ \  __/ |_| |_| | |_) |
            | .__/|_|  \___/_/\_\_| |_| |_|\___/_/\_\___|___/\___|\__|\__,_| .__/
            |_|                                    |_____|                 |_|     v1.1.0
```

# Proxmox VE 9 Installer on Debian 13 Trixie

This setup/script automates the installation of **Proxmox VE 9** on **Debian 13 Trixie** and creates a network bridge to facilitate configuration.

**Note: This script is designed to run on a Debian 13 system. Make sure to have superuser permissions before executing the script.**

## Requirements

- Debian 13 Trixie installed
- Superuser (root) permissions
  ```bash
  su root
  ```
- Git installed
  ```bash
  apt install git
  ```
- Clone the repository from the root directory:
  ```bash
  cd /
  ```

## Installation Instructions

### 1. Clone the repository

```bash
# Clone the repository to your Debian 13 system
git clone https://github.com/tjengbudi/proxmox-debian13.git

# Navigate to the downloaded folder
cd /proxmox-debian13
```

### 2. Make the script executable

```bash
chmod +x ./setup
```

### 3. Run the setup

```bash
./setup
```

The installer will guide you through the installation process with an interactive menu, allowing you to:
- Choose your preferred language (English or Portuguese)
- Optionally install additional packages
- Configure network bridge (vmbr0) manually or via DHCP

## Features

### 1. Proxmox VE 9 Installation
The script automatically installs **Proxmox VE 9** on the Debian 13 Trixie base system, including:
- Proxmox VE repository configuration for Debian 13 (Trixie)
- GPG key verification for security
- Proxmox default kernel installation
- Automatic system updates and upgrades

### 2. Network Bridge Configuration
Facilitates network configuration by creating a bridge named **vmbr0**. You can choose to:
- Configure manually with static IP address
- Use DHCP for automatic configuration
- Configure later through Proxmox web interface

### 3. Additional Packages (Optional)
The script offers optional installation of useful packages:
- **sudo** - Essential tool to grant administrative permissions
- **nala** - Enhanced APT package manager with better UI
- **fastfetch/neofetch** - System information display tool (fastfetch for Debian 13, neofetch fallback)
- **net-tools** - Classic network utilities (ifconfig, route, etc.)
- **nmap** - Network scanning and security auditing tool

### 4. Interactive Installation
- Multi-language support (English/Portuguese)
- Whiptail-based interactive menus
- Automatic reboot handling between installation stages
- Custom welcome screen option

## What's New in Version 1.1.0

- **Upgraded to Proxmox VE 9** (from version 8)
- **Upgraded to Debian 13 Trixie** (from Debian 12 Bookworm)
- Updated repository URLs and GPG keys for Debian 13
- Updated kernel removal pattern (linux-image-6.12*)
- All paths use lowercase for consistency
- Verified compatibility with all dependencies

## Technical Details

### Repository Configuration
- **Repository URL:** `http://download.proxmox.com/debian/pve trixie pve-no-subscription`
- **GPG Key:** `https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg`

### Installed Components
- **Proxmox VE 9** packages
- **Proxmox default kernel** for Debian 13
- **Postfix** - Mail transfer agent
- **Open-iSCSI** - iSCSI initiator
- **Chrony** - NTP time synchronization

### Post-Installation Access
After successful installation, access the Proxmox web interface at:
```
https://[your-server-ip]:8006/
```
- **Username:** root
- **Password:** (your root password)

## System Requirements

- Minimum **1.5GB RAM** (recommended 2GB or more)
- 64-bit processor with virtualization support (Intel VT-x or AMD-V)
- At least **20GB** disk space
- Network interface with internet connectivity

## Support and Issues

For support or to report issues, please [open an issue](https://github.com/tjengbudi/proxmox-debian13/issues).

## License

This script is distributed under the [BSD 3-Clause License](https://opensource.org/licenses/BSD-3-Clause).

## Credits

- Original script by [Matheew Alves](https://github.com/mathewalves)
- Modified and updated to Proxmox VE 9 / Debian 13 by [tjengbudi](https://github.com/tjengbudi)

## Contributing

If you find opportunities for improvement or would like to contribute, feel free to create a pull request. Contributions are welcome to enhance this script.

We appreciate your participation in the community and your contribution to the ongoing development of this script.

**Enjoy Proxmox VE 9!** 🚀
