# README: Creating a Custom Ubuntu 22.04 ISO with a First-Login Script Using Cubic

## Overview

This document describes how to use [Cubic](https://launchpad.net/cubic) (Custom Ubuntu ISO Creator) to modify an official Ubuntu 22.04 Desktop ISO so that, once installed, the system will fetch and run a remote script **on the first user login** and then remove itself. This approach is handy if you want minimal customization without implementing a full unattended install or complex cloud-init configuration.

## Prerequisites

1. **Ubuntu-based host machine**: You must have an Ubuntu-based system on which you will install and run Cubic.
2. **Ubuntu 22.04 Desktop ISO**: Download the official `ubuntu-22.04-desktop-amd64.iso` (or any flavor that you prefer).
3. **Cubic**: Install Cubic with:
   ```bash
   sudo apt update
   sudo apt install cubic
   ```

## Steps

### 1. Launch Cubic

1. Open Cubic from your **Applications** menu or by running:
   ```bash
   cubic
   ```
2. Cubic will prompt you to:
   - Select the **ISO file** (e.g., `ubuntu-22.04-desktop-amd64.iso`).
   - Choose or create a **project folder** where Cubic will unpack and store the ISO files.

### 2. Proceed to the Cubic Terminal (Chroot Environment)

After you select the ISO and project folder, Cubic will extract the ISO and eventually present you with a **terminal** window which gives you a chroot environment. Anything you do in this terminal affects the future **live environment** (and thereby the installed system).

### 3. Create the Autostart File

We will place a `.desktop` file into `/etc/skel/.config/autostart`. This ensures that *every new user* created on the installed system automatically inherits that file in their `~/.config/autostart` folder.

1. In the Cubic chroot terminal, create the required directory (if it doesn’t already exist):
   ```bash
   mkdir -p /etc/skel/.config/autostart
   ```
2. Create a `.desktop` file in that directory:
   ```bash
   cat <<EOF > /etc/skel/.config/autostart/run-once-remote-script.desktop
   [Desktop Entry]
   Type=Application
   Exec=/usr/local/bin/first-login-run.sh
   Hidden=false
   NoDisplay=false
   X-GNOME-Autostart-enabled=true
   Name=Run Remote Script
   Comment=Fetch and run a remote script on first login
   EOF
   ```

### 4. Create the First-Login Script

Next, we create a script in `/usr/local/bin` that the `.desktop` file calls. This script will:

1. Download a remote script.
2. Run the downloaded script.
3. Cleanup (remove itself and its autostart `.desktop` file) so that it only runs **once**.

1. In the Cubic chroot terminal, create the script:
   ```bash
   cat <<'EOF' > /usr/local/bin/first-login-run.sh
   #!/usr/bin/env bash

   # --- URL of the script you want to run ---
   REMOTE_SCRIPT_URL="https://github.com/ldabas/k3s-install-script/raw/main/k3sinstall.sh"

   # 1. Download the remote script
   wget -O /tmp/remote-script.sh "$REMOTE_SCRIPT_URL" || exit 1

   # 2. Make it executable
   chmod +x /tmp/remote-script.sh

   # 3. Run the remote script
   /tmp/remote-script.sh

   # 4. Remove the remote script
   rm /tmp/remote-script.sh

   # 5. Remove this script (so it won't run again)
   rm -f /usr/local/bin/first-login-run.sh

   # 6. Remove the .desktop file from /etc/skel (for future new users)
   rm -f /etc/skel/.config/autostart/run-once-remote-script.desktop

   # 7. Remove the .desktop file from the actual user's home
   rm -f "$HOME/.config/autostart/run-once-remote-script.desktop"

   exit 0
   EOF
   ```
2. Make the script executable:
   ```bash
   chmod +x /usr/local/bin/first-login-run.sh
   ```

At this point, the script and `.desktop` file are in place. That’s enough customization to ensure that, when someone installs Ubuntu from this custom ISO and then logs in for the first time, it will fetch and run your remote script.

### 5. Finalize Changes in Cubic

1. **Exit** or **close** the Cubic terminal.
2. Cubic will then show you various screens:
   - A manifest screen (listing packages). You don’t need to change anything there unless you want to add or remove packages.
   - A boot/ISO configuration screen (optional). Usually, defaults are fine.
3. Eventually, Cubic will show you the **Generate** page. Here you can:
   - Update the **Volume Name** (if desired).
   - Confirm the path where the **new ISO** will be created.
4. Click **Generate** to build your new ISO image. Cubic will take some time to package everything.

### 6. Test Your New ISO

1. Once Cubic finishes, you’ll have a newly generated ISO in the chosen output location (e.g., `~/cubic-project`).
2. Test it by booting it in a virtual machine (e.g. VirtualBox, GNOME Boxes, KVM, etc.).
3. **Install Ubuntu** as you normally would.
4. **Log in** for the first time on the newly installed system.
   - You should see that the script downloads and runs your remote code.
   - After the first run, it cleans itself up and will not run again.
