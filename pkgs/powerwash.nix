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
  disk = config.disko.devices.disk.main.content.partitions.ROOT;
  device = disk.device;
  homeOpts = builtins.concatStringsSep "," disk.content.subvolumes."@home".mountOptions;
  varOpts = builtins.concatStringsSep "," disk.content.subvolumes."@var".mountOptions;

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
      ### nixelOS powerwash script

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

      error() {
        printf '\n'
        gum style --foreground="$RED" "$1"
      }

      if [[ $EUID != 0 ]]; then
        gum style --foreground="$YELLOW" \
          "Error! This script requires root privileges; please re-run as root"
        exit 1
      fi
      cd /
      printf '\n'

      ### Confirm powerwashing
      gum style --bold --background="$RED" --foreground="$YELLOW" \
        "This will delete all Flatpak packages and user data!"
      gum confirm --default=false \
        "Are you sure you want to proceed?" && gum style --bold --foreground="$YELLOW" \
        "Okay, but..." || exit 0
      gum confirm --default=false \
        "...are you really sure?" && gum style \
        "Proceeding with powerwashing..." || exit 0

      ### Unmount btrfs subvolumes
      if ! umount --lazy /home /var; then
        error "An error occurred unmounting the filesystems"
        exit 1
      fi

      ### Remount subvolumes under /tmp
      MNT=$(mktemp -d -t btrfs-XXXXX)
      mount ${device} "$MNT"
      ### Unmount & remove /tmp directory on exit
      trap 'umount "$MNT"; rm -rf "$MNT"' EXIT

      ### Delete existing home subvolume & restore from snapshot
      gum spin \
        --title "Deleting /home subvolume..." \
        -- btrfs subvolume delete "$MNT"/@home || error "An error occurred deleting the @home subvolume"
      gum spin \
        --title "Restoring /home from snapshot..." \
        -- btrfs subvolume snapshot "$MNT"/@snaps/home-snap "$MNT"/@home || error "An error occurred restoring the @home subvolume"

      ### Remove specific /var directories
      gum spin \
        --title "Removing Flatpaks and miscellaneous data..." \
        -- rm -rf \
        "$MNT"/@var/log \
        "$MNT"/@var/lib/flatpak \
        "$MNT"/@var/lib/NetworkManager || error "An error occurred removing /var directories"

      ### Copy default /var/log directory from snapshot
      gum spin \
        --title "Restoring /var/log from snapshot..." \
        -- cp -r "$MNT"/@snaps/var-snap/log "$MNT"/@var/ || error "An error occurred restoring log directory"

      ### Remount newly-restored subvolumes
      gum spin \
        --title "Mounting /home..." \
        -- mount -o ${homeOpts},subvol=@home /home || error "An error occurred re-mounting the /home filesystem"
      gum spin \
        --title "Mounting /var..." \
        -- mount -o ${varOpts},subvol=@var /var || error "An error occurred re-mounting the /var filesystem"

      ### Re-install Flatpaks
      if ! gum spin \
        --title "Re-installing default Flatpaks. This can take several minutes..." \
        -- systemctl start flatpak-managed-install-timer.service;
      then
        error "There was an error re-installing the Flatpaks"
      else
        gum style --foreground="$BLUE" \
          "Default Flatpaks have been re-installed"
      fi

      ### Clean system
      gum spin --show-output \
        --title "Collecting Nix garbage..." \
        -- nix-collect-garbage -d || error "There was an error collecting the garbage"

      ### Remove previous network connection(s)
      gum spin \
        --title "Removing previous network connection(s)..." \
        -- rm -rf /etc/NetworkManager/{system-connections,VPN} || error "An error occurred removing the network connection(s)"

      ### Rebuild system
      if ! gum spin --show-output \
        --title "Rebuilding the system..." \
        -- nixos-rebuild switch --flake /etc/nixos#nixel;
      then
        error "There was an error rebullding the system"
        exit 1
      else
        ### Prompt for reboot
        gum style --foreground="$GREEN" \
          "Finished! Make sure to reboot for changes to take effect" && printf '\n'
        gum confirm \
          --affirmative="Reboot now" \
          --negative="Reboot later" \
          "Would you like to reboot now?" && systemctl reboot || exit 0
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
