![nixelOS](https://github.com/user-attachments/assets/bf1974f6-11cc-4519-872d-cfdda66139b5)

This is meant to be a simple and easy to deploy version of NixOS imitating
ChromeOS, hence the play on the word Nickel. It's a very minimal install that
uses NixOS for easy upgrades/rollbacks, utilizes Flatpaks for application
installs, and runs the Cinnamon DE to give a familiar feel for incoming Windows
users. Auto upgrades pull from this repository and run on a weekly basis.

Ideally, this can be deployed to a friend or family member's computer, most
likely with the assistance of a somewhat tech-savvy individual (I built this
with my mother in mind). All that's required is booting from the NixOS installer,
running the single command, and answering the prompts that follow.

The recommended minimum system specs are at least 8GB of RAM and a 32GB disk.

nixelOS is currently utilizing:
- Nixpkgs: nixos-25.05
- Linux Kernel: LTS 6.12

#### Disk Layout

The included Disko module handles automated formatting, so other than selecting
which disk to use for installation, no complicated disk interactions are required.
The disk will be formatted, split into three partitions (mbr/uefi/root), and
setup a btrfs file system. A swap file will also be created matching the amount
of system RAM installed. It goes without saying to make sure any data and/or
partition(s) are backed up prior to running this, as they will be lost once
formatting completes.

Here's an example layout using `lsblk` from a virtual machine running this flake:

```bash
NAME     SIZE TYPE MOUNTPOINTS
vda       32G disk
├─vda1     1M part
├─vda2   512M part /boot
└─vda3  31.5G part /home
                   /.snapshots
                   /.swap
                   /nix
                   /var
                   /
```

## Installation

**NOTE:** NixOS does not currently support 'Secure Boot', so make sure it's disabled
in your BIOS/UEFI firmware or the installer will not boot!

Once the NixOS installer has booted, run the following command:

```nix
sudo nix --experimental-features "nix-command flakes" run github:j-pap/nixelOS
```

After the script has initialized, you'll be prompted for the following four items
before proceeding with formatting and installation:
- Install disk (all disks displayed & confirmation to verify correct disk)
- Host name (only letters, numbers, and hyphens allowed; 63 character max)
- User name (only letters allowed; 32 character max)
- Password (confirmation to verify the password was typed correctly; then hashed)

A variables.nix file will be generated containing these values, which is used as
a template for several definitions used throughout the system configuration.

## Post-install

#### Flatpak Delay

After initial login, a set of Flatpaks (LibreOffice & VLC) will be installed,
however, they won't show up in the applications menu until a reboot is performed.
Upon reboot, those Flatpaks should now show up and be available for use. The
software store will also have Flathub integration, so additional apps can then
also be searched for & installed.

#### Rebuilding

**NOTE:** Make sure to stash or commit any changes you make, as the weekly
upgrade will perform a hard reset on /etc/nixos.

A `nixel-rebuild` alias has been setup that redirects to:
```bash
sudo nixos-rebuild switch --flake /etc/nixos#nixel
```
If a manual rebuild is ever required, the flake option and argument are required
or else the rebuild will fail (assuming that the host name was changed from the
default of 'nixel'). Hence, the alias to make it easier to remember & perform.

#### Powerwashing

If you ever want and/or need to remove your user data, there's a utility in the
applications menu named 'Powerwash' that can be ran; or from a terminal, run:
```bash
sudo powerwash
```
This will remove the /home subvolume, along with any Flatpaks, logs, and network
connections. Once the powerwash is completed, a reboot will be required for any
changes to take effect. Upon reboot, you should have a bare-bones system again.

### Credits

After getting the hang of Nix, I started getting the urge to build a Nix-ified
ChromeOS alternative that the average person could benefit from. After attending
SCaLE 22x where I sat in on [Michael Kelly's nixbook](https://github.com/mkellyxp/nixbook) presentation,
I finally decided to move forward with my own variant and way of doing things.
He's put a lot of time & effort into nixbook, so you should go check that out as
well.
