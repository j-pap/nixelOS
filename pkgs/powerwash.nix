{
  stdenv,
  lib,
  writeShellApplication,
  makeDesktopItem,
  bash,
  btrfs-progs,
  gnome-terminal,
  gum,
  nix,
  nixos-rebuild,
  config,
}:

let
  diskDev = config.disko.devices.disk.main.content.partitions.ROOT.device;

  name = "powerwash";

  desktop = makeDesktopItem {
    inherit name;
    desktopName = lib.toSentenceCase name;
    categories = [ "Utility" ];
    comment = "Remove all user data and restore the system to image defaults";
    exec = "${lib.getExe gnome-terminal} -- sudo ${lib.getExe script}";
    terminal = true;
  };

  script = writeShellApplication {
    inherit name;
    runtimeInputs = [
      bash
      btrfs-progs
      gum
      nix
      nixos-rebuild
    ];
    text = ''
      #
      ### NixOS powerwash script

      set -e
      BLUE="#00FFFF"
      GREEN="#00FF00"
      PINK="#FF00FF"
      PURPLE="#8000FF"
      RED="#FF0000"
      YELLOW="#FFFF00"
      export GUM_CHOOSE_CURSOR_FOREGROUND="$BLUE"
      export GUM_CONFIRM_PROMPT_FOREGROUND="$RED"
      export GUM_CONFIRM_SELECTED_BACKGROUND="$PINK"
      export GUM_CONFIRM_SELECTED_FOREGROUND="$YELLOW"
      export GUM_SPIN_SPINNER="points"
      export GUM_SPIN_SPINNER_FOREGROUND="$PURPLE"
      export GUM_SPIN_TITLE_FOREGROUND="$WHITE"

      if [[ $EUID != 0 ]]; then
        gum style "Error! This script requires root privileges; please re-run as root" --foreground="$YELLOW"
        exit 1
      fi
      cd /
      printf '\n'

      ### Confirm powerwashing
      gum style "This will delete all Flatpak packages and user data!" --bold --background="$RED" --foreground="$YELLOW"
      gum confirm "Are you sure you want to proceed?" --default=false && gum style 'Okay, but...' --bold --foreground="$YELLOW" || exit 0
      gum confirm "...are you really sure?" --default=false && gum style 'Proceeding with powerwashing...' || exit 0

      ### Unmount btrfs subvolumes
      if ! umount --lazy /home /var; then
        gum style "An error occurred unmounting the filesystems" --foreground="$RED"
        exit 1
      fi

      ### Remount subvolumes under /tmp
      MNT=$(mktemp -d -t btrfs-XXXXX)
      mount ${diskDev} "$MNT"
      ### Unmount & remove /tmp directory on exit
      trap 'umount "$MNT"; rm -rf "$MNT"' EXIT

      ### Delete existing home subvolume & restore from snapshot
      gum spin --title "Deleting /home subvolume..." -- btrfs subvolume delete "$MNT"/@home || gum style "An error occurred deleting the @home subvolume" --foreground="$RED"
      gum spin --title "Restoring /home from snapshot..." -- btrfs subvolume snapshot "$MNT"/@snaps/home-snap "$MNT"/@home || gum style "An error occurred restoring the @home subvolume" --foreground="$RED"

      ### Remove specific /var directories
      gum spin --title "Removing Flatpaks and miscellaneous data..." -- rm -rf \
        "$MNT"/@var/log \
        "$MNT"/@var/lib/flatpak \
        "$MNT"/@var/lib/NetworkManager || gum style "An error occurred removing /var directories" --foreground="$RED"

      ### Copy default /var/log directory from snapshot
      gum spin --title "Restoring /var/log from snapshot..." -- cp -r "$MNT"/@snaps/var-snap/log "$MNT"/@var/ || gum style "An error occurred restoring log directory" --foreground="$RED"

      ### Remount newly-restored subvolumes
      gum spin --title "Mounting /home..." -- mount -o compress=zstd,discard=async,subvol=@home /home || gum style "An error occurred re-mounting the /home filesystem" --foreground="$RED"
      gum spin --title "Mounting /var..." -- mount -o compress=zstd,discard=async,noatime,subvol=@var /var || gum style "An error occurred re-mounting the /var filesystem" --foreground="$RED"

      ### Re-install Flatpaks
      if ! gum spin --title "Re-installing default Flatpaks. This can take several minutes..." -- systemctl start flatpak-managed-install-timer.service; then
        gum style "There was an error re-installing the Flatpaks" --foreground="$RED"
      else
        gum style "Default Flatpaks have been re-installed" --foreground="$BLUE"
      fi

      ### Clean system
      gum spin --title "Collecting Nix garbage..." --show-output -- nix-collect-garbage -d || gum style "There was an error collecting the garbage" --foreground="$RED"

      ### Rebuild system
      if ! gum spin --title "Rebuilding the system..." --show-output -- nixos-rebuild switch --flake /etc/nixos#nixel; then
        gum style "There was an error rebullding the system" --foreground="$RED"
        exit 1
      else
        ### Prompt for reboot
        gum style "Finished! Make sure to reboot for changes to take effect" --foreground="$GREEN"
        gum confirm "Would you like to reboot now?" --affirmative="Reboot now" --negative="Reboot later" && systemctl reboot || exit 0
      fi
    '';
  };
in

stdenv.mkDerivation {
  inherit name;
  buildCommand = ''
    mkdir -p "$out"/bin "$out"/share/applications
    cp ${script}/bin/${name} "$out"/bin/
    cp ${desktop}/share/applications/${name}.desktop "$out"/share/applications/
  '';
}
