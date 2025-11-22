


# XOs Linux

**XOs** is a custom Arch Linux–based distribution focused on simplicity, clean X branding, and reproducible builds.  
This repository contains the full ArchISO profile and post-installation assets used to generate the official XOs ISO image.

> **Project status:** Under active development  

---

## Overview

XOs aims to provide a minimal yet polished Arch-based system with its own identity and branding.  
It is built entirely from official Arch repositories, using the standard `mkarchiso` workflow with a custom profile definition and post-install scripts.

---

## Project Structure

```

xos/
├── profiledef.sh             # ArchISO profile definition
├── pacman.conf               # Custom package configuration
├── packages.x86_64           # Package list for ISO build
├── airootfs/                 # Root filesystem (customized ArchISO overlay)
│   ├── etc/
│   ├── root/
│   └── ...
├── root/
│   └── xos-assets/           # Branding, wallpapers, logos, postinstall scripts
│       ├── xos-postinstall.sh
│       ├── logos/
│       ├── backgrounds/
│       └── ...
├── build.sh                  # Automated build script
└── .gitignore

````

---

## Building the ISO

To build the XOs ISO image locally, ensure you have `archiso` installed.

```bash
sudo pacman -S archiso
````

Then run the included build script:

```bash
./xbuild.sh
```

The script will:

1. Unmount any stale mounts from previous builds.
2. Clean the `work/` and `out/` directories.
3. Run `mkarchiso` with the provided configuration.
4. Store the resulting `.iso` image inside `./out/`.

Example output:

```
out/
└── XOs-YYYY.MM.DD-x86_64.iso
```

---

## Post-installation Customization

After installing Arch via the generated ISO, execute the **XOs post-install script** to apply full system branding and configuration.

```bash
sudo /root/xos-assets/xos-postinstall.sh
```

This script:

* Rewrites `/etc/os-release` to identify the system as XOs Linux.
* Installs wallpapers, logos, and GDM/GNOME branding.
* Sets up post-install hooks and environment adjustments.

---

## Notes

* The repository ignores build outputs (`work/`, `out/`, logs) for cleaner commits.
* All configuration and assets required to reproduce the ISO are included.
* For development or debugging, you can modify files under `airootfs/` and rebuild.

---

## License

All build scripts and configuration files are released under the MIT License,
unless stated otherwise in subdirectories (e.g., artwork or third-party themes).

---

## Author

**Xscriptor**
[github.com/xscriptor](https://github.com/xscriptor)

---


