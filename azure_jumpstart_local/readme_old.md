# Automated Ubuntu 22.04 Installation with Post-Install Interactive Script

This guide explains how to create a **fully automated** Ubuntu 22.04 LTS installation (using Subiquity's "autoinstall" feature) **and** run an **interactive script** upon the **first user login** after installation. This approach ensures that you can configure additional settings (that require user input and possibly network access) without interrupting the initial installation flow.

---

## Table of Contents

- [Automated Ubuntu 22.04 Installation with Post-Install Interactive Script](#automated-ubuntu-2204-installation-with-post-install-interactive-script)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Requirements](#requirements)
  - [Folder Structure](#folder-structure)
  - [Step 1: Prepare the Autoinstall Configuration File](#step-1-prepare-the-autoinstall-configuration-file)
  - [Step 4: Integrate Into Your ISO or Boot Media](#step-4-integrate-into-your-iso-or-boot-media)
    - [Option A: Custom ISO Remastering](#option-a-custom-iso-remastering)
  - [Step 5: Test the Installation](#step-5-test-the-installation)

---

## Overview

- **Goal**: Install Ubuntu 22.04 LTS with **no prompts** during the installation itself and only **prompt** the user for additional setup **after** the system finishes installing and reboots.
- **Method**: 
  1. Use Ubuntu's [autoinstall](https://ubuntu.com/server/docs/install/autoinstall) feature (the YAML-based replacement for legacy preseed/kickstart).
  2. Copy a script to the newly installed system in the `late-commands` phase.
  3. Place a small script in `/etc/profile.d/` that executes **once** upon the **first login**, prompting for user input.

This approach is simpler and more reliable for interactive prompts because by the time the user logs in, there is a guaranteed interactive shell (TTY or SSH) and the network is typically ready.

---

## Requirements

1. **Ubuntu 22.04 ISO** – Typically the server ISO or a customized version that supports autoinstall.
2. **Autoinstall YAML** – A configuration file (often named `user-data` or `autoinstall.yaml`).
3. **Script** – A custom shell script (`post_install.sh`) that you want to run interactively after the OS is installed.
4. **Ability to Modify ISO** – You'll need to either:
   - Remaster the ISO to include your YAML and script files.  
   - Or provide them via a boot parameter (`ds=nocloud-net;s=<URL>`) if you can host them on a network location.

---

## Folder Structure

A possible structure for your project (e.g., a GitHub repository):

```
├── README.md          # This documentation file 
├── autoinstall.yaml   # Your YAML config for the automated installation 
└── post_install.sh    # The interactive script that runs post-install
```

When building the ISO or preparing your boot media:

1. Place `autoinstall.yaml` (or `user-data` + `meta-data` if using NoCloud) on the ISO/USB.
2. Place `post_install.sh` on the root of the ISO so that it appears under `/cdrom/` during installation.

---

## Step 1: Prepare the Autoinstall Configuration File

Below is a sample `autoinstall.yaml`. It performs a basic automated installation:

```yaml
# File: autoinstall.yaml

autoinstall:
  version: 1
  
  # Basic user + hostname configuration
  identity:
    hostname: myserver
    username: ubuntu
    # The password here is hashed (for example, "ubuntu" hashed).
    # Generate your own hash using: mkpasswd --method=SHA-512 --rounds=4096
    password: "$6$5r9K3GVrB9lxUb$.9XCgJ6OVkM4mUEBlpxqkPs1GQjgpAmn1fspu2guV3B89KWgbGo6NvKb5iaLp9y/d20Ktc6Ya3bdPGB8rD5mW1"
  
  # Storage: wipe disk and install
  storage:
    layout:
      name: direct
      match:
        size: largest
    config: []
  
  # (Optional) Network config, extra users, SSH keys, etc.

  # Late commands: where we copy and set up the post-install script
  late-commands:
    - "curtin in-target --target=/target -- cp /cdrom/post_install.sh /root/post_install.sh"
    - "curtin in-target --target=/target -- chmod +x /root/post_install.sh"
    - |
      curtin in-target --target=/target -- bash -c "cat << 'EOF' > /etc/profile.d/first_login_post_install.sh
      #!/usr/bin/env bash
      LOCK_FILE=/root/.post_install_ran

      if [ ! -f \${LOCK_FILE} ]; then
        /root/post_install.sh
        touch \${LOCK_FILE}
      fi
      EOF"
    - "curtin in-target --target=/target -- chmod +x /etc/profile.d/first_login_post_install.sh"

  # Automatically reboot after install finishes
  power_state:
    mode: reboot
```

Explanation:

- `curtin in-target --target=/target` enters the newly installed system environment (mounted at `/target`) to run commands inside it.
- We copy `post_install.sh` from `/cdrom/` into `/root/` of the target system.
- We create `first_login_post_install.sh` inside `/etc/profile.d/`. This script checks for a “lock” file and, if it doesn’t exist, runs our `post_install.sh` (which will prompt the user).
- We set a lock file (`/root/.post_install_ran`) so we only do this once.


Step 2: Create Your Post-Install Script
Write a script named `post_install.sh`. For instance:

```bash
# File: post_install.sh

INSERT POSDT INSTALL SCRIPT HERE
```


Step 3: Update the Late Commands in the YAML
Make sure the paths in your YAML match where you placed post_install.sh on the ISO. If you put post_install.sh in a folder (like /cdrom/scripts/), adjust accordingly:

```
  # Late commands: where we copy and set up the post-install script
  late-commands:
    - "curtin in-target --target=/target -- cp /cdrom/scripts/k3sinstall.sh /root/k3sinstall.sh"
    - "curtin in-target --target=/target -- chmod +x /root/k3sinstall.sh"
    - |
      curtin in-target --target=/target -- bash -c "cat << 'EOF' > /etc/profile.d/first_login_post_install.sh
      #!/usr/bin/env bash
      LOCK_FILE=/root/.post_install_ran

      if [ ! -f \${LOCK_FILE} ]; then
        /root/k3sinstall.sh
        touch \${LOCK_FILE}
      fi
      EOF"
    - "curtin in-target --target=/target -- chmod +x /etc/profile.d/first_login_post_install.sh"

```

## Step 4: Integrate Into Your ISO or Boot Media

### Option A: Custom ISO Remastering

1. Mount the official Ubuntu 22.04 ISO
2. Copy `autoinstall.yaml` to the ISO's root or a folder where Subiquity can read it
3. Copy `k3sinstall.sh` to the root of the ISO (or whichever folder you used in your YAML)
4. Update the ISO's kernel boot parameters to include:
   ```bash
   autoinstall ds=nocloud;s=/cdrom/
   ```
   so Subiquity knows to look at `/cdrom/` for `user-data` (and `meta-data` if needed)
5. Repack the ISO (using tools like Cubic or manually with xorriso)



## Step 5: Test the Installation

1. Boot your new or modified ISO (or use the boot parameter approach) in a VM (e.g., VirtualBox, QEMU, VMware) or on a test machine
2. Observe that the installer proceeds without asking for manual input
3. Wait for the installation to complete and the system to reboot
4. Login (console or SSH):
   - Immediately upon login, the system sources everything in `/etc/profile.d/`, triggering `first_login_post_install.sh`
   - That script checks `/root/.post_install_ran`
   - If it doesn't exist, it runs `/root/k3sinstall.sh` (your interactive script)
   - Afterwards, it creates `/root/.post_install_ran` so it won't run again on subsequent logins
5. Enter any required data (e.g., new hostname) and confirm the changes or installations happen as expected
6. Logout and log back in – The script should not run again, because the lock file is set
