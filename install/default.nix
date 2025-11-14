{
  writeShellApplication,
  bash,
  disko,
  gitMinimal,
  gum,
  nix,
}:

writeShellApplication {
  name = "install";
  runtimeInputs = [
    bash
    disko
    gitMinimal
    gum
    nix
  ];
  text = ''
    #
    ### NixOS installation script

    set -e
    BLUE="#00FFFF"
    GREEN="#00FF00"
    PINK="#FF00FF"
    PURPLE="#8000FF"
    RED="#FF0000"
    YELLOW="#FFFF00"
    WHITE="#FFFFFF"
    export GUM_CHOOSE_CURSOR_FOREGROUND="$PINK"
    export GUM_CHOOSE_HEADER_FOREGROUND="$BLUE"
    export GUM_CONFIRM_PROMPT_FOREGROUND="$RED"
    export GUM_CONFIRM_SELECTED_BACKGROUND="$PINK"
    export GUM_CONFIRM_SELECTED_FOREGROUND="$YELLOW"
    export GUM_INPUT_HEADER_FOREGROUND="$BLUE"
    export GUM_INPUT_PROMPT_FOREGROUND="$PURPLE"
    export GUM_SPIN_SPINNER="points"
    export GUM_SPIN_SPINNER_FOREGROUND="$PURPLE"
    export GUM_SPIN_TITLE_FOREGROUND="$WHITE"

    if [[ $EUID != 0 ]]; then
      gum style "Error! This script requires root privileges; please re-run as root" --foreground="$YELLOW"
      exit 1
    fi
    clear
    printf '\n'

    ### USER PROMPTS
    ###
    ### Display available disk(s) and their size/mount(s)
    DISK_COL_HEADER="$(lsblk -o name,size,mountpoints | grep 'NAME')"
    gum style "$DISK_COL_HEADER" --foreground="$WHITE"
    lsblk -o name,size,mountpoints | grep 'nvme[0-9]n[0-9]\|sd[a-z]\|vd[a-z]\|hd[a-z]'
    printf '\n'

    ### Put disks into array
    mapfile -t SYS_DISKS < <(find "/dev" -regex '/dev/nvme[0-9]n[0-9]\|/dev/sd[a-z]\|/dev/vd[a-z]\|/dev/hd[a-z]' | sort)
    if (( ''${#SYS_DISKS[@]} == 0 )); then
      gum style "No disk devices were found! Quitting..." --foreground="$YELLOW" >&2
      exit 1
    fi

    ### Prompt from array for installation disk
    while true; do
      DISK=$(gum choose --header="Select a disk to be formatted for installation:" "''${SYS_DISKS[@]}")
      if [ -z "$DISK" ]; then
        gum style "A disk must be selected!" --foreground="$YELLOW" && printf '\n'
      else
        gum confirm "Are you sure you want to use $DISK?" --default=false && break || printf '\n'
      fi
    done
    clear
    printf '\n'

    ### Prompt for host name
    while true; do
      HOST=$(gum input --header="What will the system's host name be?" --char-limit=63 --placeholder="host name" --value="nixel")
      if [ -z "$HOST" ]; then
        gum style "Host name cannot be blank!" --foreground="$YELLOW" && printf '\n'
      elif [[ "$HOST" =~ [^A-Za-z0-9-] ]]; then
        gum style "Only letters, numbers, and hyphens are allowed (no spaces)!" --foreground="$YELLOW" && printf '\n'
      else
        break
      fi
    done

    ### Prompt for user name
    while true; do
      USER=$(gum input --header="What will your user name be?" --char-limit=32 --placeholder="user name" | tr "[:upper:]" "[:lower:]")
      if [ -z "$USER" ]; then
        gum style "You must set a User name!" --foreground="$YELLOW" && printf '\n'
      elif [[ "$USER" =~ [^a-z] ]]; then
        gum style "Only letters are allowed (no spaces)!" --foreground="$YELLOW" && printf '\n'
      else
        break
      fi
    done

    ### Prompt for user password & hash it
    while true; do
      PASS=$(gum input --header="What password would you like to assign to $USER?" --password --placeholder="password")
      PASS2=$(gum input --header="Re-enter password for verification: " --password --placeholder="confirm")
      if [ -z "$PASS" ] || [ -z "$PASS2" ]; then
        gum style "You cannot set an empty user password!" --foreground="$YELLOW" && printf '\n'
      elif [ "$PASS" = "$PASS2" ]; then
        break
      else
        gum style "The passwords do not match! Please try again" --foreground="$YELLOW" && printf '\n'
      fi
    done
    HASH=$(echo -n "$PASS" | mkpasswd --method=SHA-512 --stdin)

    ### Prompt for time zone
    while true; do
      TMZN=$(timedatectl list-timezones | gum choose --header="Select your time zone:" --ordered --height=30 --limit=1)
      if [ -z "$TMZN" ]; then
        gum style "A time zone must be selected!" --foreground="$YELLOW" && printf '\n'
      else
        gum confirm "Are you sure you want to select '$TMZN'?" --default=false && break || printf '\n'
      fi
    done
    clear
    printf '\n'

    ###
    ### GENERATE FILES / FORMAT DISK
    ###
    ### Create /tmp directory
    NIXDIR=$(mktemp -d -t nixos-XXXXX)

    ### Clone git repo into /tmp for disko & create new git branch
    if ! gum spin --title "Cloning Git repo..." -- git clone https://github.com/j-pap/nixelOS.git "$NIXDIR"; then
      gum style "Failed to clone Git repository!" --foreground="$RED"
      exit 1
    fi
    cd "$NIXDIR"
    gum spin --title "Creating new Git branch..." --show-error -- git switch -c deployment

    ### Generate .nix configuration files
    gum spin --title "Generating NixOS configuration files..." --show-error -- nixos-generate-config --no-filesystems --dir "$NIXDIR"

    ### Copy system.stateVersion to hardware-configuration.nix
    STATE=$(grep "system.stateVersion = *" "$NIXDIR"/configuration.nix | sed 's/ #.*//')
    sed -i "$ i\\\n$STATE" "$NIXDIR"/hardware-configuration.nix

    ### ...and then move & remove respective generated .nix configs
    mkdir -p "$NIXDIR"/host
    mv "$NIXDIR"/hardware-configuration.nix "$NIXDIR"/host/hardware-configuration.nix
    rm -f "$NIXDIR"/configuration.nix

    ### Calculate and round the amount of system RAM for swap
    RAM=$(awk '/^MemTotal/{ print $2/1000/1000 }' < /proc/meminfo | numfmt --to iec --suffix G)

    ### Generate variables.nix from user prompts/swap calculation
    cat > "$NIXDIR"/host/variables.nix << EOF
    {
      _module.args.vars = {
        disk = "$DISK";
        host = "$HOST";
        user = "$USER";
        pass = "$HASH";
        time = "$TMZN";
        swap.size = "$RAM";
        swap.offset = "";
      };
    }
    EOF

    ### Format & mount via disko
    if gum spin --title "Formatting & mounting disk..." --show-error -- disko --mode disko --flake "$NIXDIR"#nixel; then
      gum style "Formatting complete!" --foreground="$GREEN"
    else
      printf '\n'
      gum style "Formatting failed! Please try again" --foreground="$RED"
      exit 1
    fi

    ### Calculate swap offset post-formatting and insert into variables.nix
    OFFSET=$(btrfs inspect-internal map-swapfile -r /mnt/.swap/swapfile)
    sed -i "9s/\".*\"/\"$OFFSET\"/" "$NIXDIR"/host/variables.nix

    ### Update flake.lock
    gum spin --title "Updating flake.lock..." --show-error -- nix flake update --refresh

    ### Copy repo from /tmp to formatted install disk
    mkdir -p /mnt/etc/nixos && cd "$_"
    cp -ar "$NIXDIR"/. /mnt/etc/nixos

    ### Commit generated .nix files so they build with install
    git add /mnt/etc/nixos
    { git -c user.email="nixel@null.local" -c user.name="nixel" commit -m "Committed .nix files generated @ install" > /dev/null; } 2>&1

    ###
    ### INSTALLATION / FINALIZATION
    ###
    ### NixOS installation
    gum style "Performing installation, please be patient..." --foreground="$BLUE"
    printf '\n'
    if ! nixos-install --no-root-passwd --flake /mnt/etc/nixos#nixel; then
      printf '\n'
      gum style "Installation failed! Please try again" --foreground="$RED"
      exit 1
    fi

    ### Create XDG directories
    install -d -m 755 -o 1000 -g 100 /mnt/home/"$USER"/{.config/cinnamon/backgrounds,Desktop,Documents,Downloads,Music,Pictures,Videos}

    ### Create Cinnamon desktop background source directory list
    chown -R 1000:100 /mnt/home/"$USER"/.config/
    install -m 755 -o 1000 -g 100 <(cat << EOF
    /home/$USER/Pictures
    /run/current-system/sw/share/backgrounds/gnome
    /run/current-system/sw/share/backgrounds/nixos
    EOF
    ) /mnt/home/"$USER"/.config/cinnamon/backgrounds/user-folders.lst

    ### Create post-install snapshots of /home & /var for potential powerwashing
    gum spin --title "Taking snapshot of /home..." -- btrfs subvolume snapshot -r /mnt/home /mnt/.snapshots/home-snap > /dev/null
    gum spin --title "Taking snapshot of /var..." -- btrfs subvolume snapshot -r /mnt/var /mnt/.snapshots/var-snap > /dev/null

    printf '\n'
    gum style "Installation complete! Please reboot when ready" --foreground="$GREEN"
  '';
}
