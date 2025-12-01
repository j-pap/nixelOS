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
    ### nixelOS installation script

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
    export GUM_CONFIRM_PROMPT_FOREGROUND="$YELLOW"
    export GUM_CONFIRM_SELECTED_BACKGROUND="$PINK"
    export GUM_CONFIRM_SELECTED_FOREGROUND="$YELLOW"
    export GUM_INPUT_HEADER_FOREGROUND="$BLUE"
    export GUM_INPUT_PROMPT_FOREGROUND="$PURPLE"
    export GUM_SPIN_SPINNER="points"
    export GUM_SPIN_SPINNER_FOREGROUND="$PURPLE"
    export GUM_SPIN_TITLE_FOREGROUND="$WHITE"

    warn() {
      clear && printf '\n'
      gum style --foreground="$YELLOW" "$1"
      printf '\n'
    }

    error() {
      printf '\n'
      gum style --foreground="$RED" "$1"
    }

    if [[ $EUID != 0 ]]; then
      warn "Error! This script requires root privileges; please re-run as root"
      exit 1
    fi
    clear && printf '\n'

    ###
    ### USER PROMPTS
    ###
    ### Put disk(s) into array
    mapfile -t SYS_DISKS < <(find "/dev" -regex '/dev/nvme[0-9]n[0-9]\|/dev/sd[a-z]\|/dev/vd[a-z]\|/dev/hd[a-z]' | sort)
    if (( ''${#SYS_DISKS[@]} == 0 )); then
      warn "No disk devices were found! Quitting..." >&2
      exit 1
    fi

    ### Display & select installation disk
    while true; do
      ### Display header columns/available disk(s) & their size/mount(s)
      gum style --foreground="$WHITE" \
        "$(lsblk -o name,size,mountpoints | grep 'NAME')"
      lsblk -o name,size,mountpoints | grep 'nvme[0-9]n[0-9]\|sd[a-z]\|vd[a-z]\|hd[a-z]'
      printf '\n'

      ### Prompt for installation disk from array
      DISK=$(gum choose \
        --header="Select a disk to be formatted for installation:" \
        "''${SYS_DISKS[@]}"
      )
      if [ -z "$DISK" ]; then
        warn "A disk must be selected!"
      else
        gum confirm --default=false \
          "Are you sure you want to use $DISK?" && break || printf '\n'
      fi
    done
    clear && printf '\n'

    ### Prompt for hostname
    while true; do
      HOST=$(gum input --char-limit=63 \
        --placeholder="hostname" --value="nixel" \
        --header="What will the system's hostname be?"
      )
      if [ -z "$HOST" ]; then
        warn "Hostname cannot be blank!"
      elif [[ "$HOST" =~ [^A-Za-z0-9-] ]]; then
        warn "Only letters, numbers, and hyphens are allowed (no spaces)!"
      else
        break
      fi
    done
    clear && printf '\n'

    ### Prompt for user name
    while true; do
      USER=$(gum input --char-limit=32 \
        --placeholder="user name" \
        --header="What will your user name be?" | tr "[:upper:]" "[:lower:]"
      )
      if [ -z "$USER" ]; then
        warn "You must set a user name!"
      elif [[ "$USER" =~ [^a-z] ]]; then
        warn "Only letters are allowed (no spaces)!"
      else
        break
      fi
    done
    clear && printf '\n'

    ### Prompt for user password & hash it
    while true; do
      PASS=$(gum input --password \
        --placeholder="password" \
        --header="What password would you like to assign to $USER?"
      )
      PASS2=$(gum input --password \
        --placeholder="confirm" \
        --header="Re-enter password for verification:"
      )
      if [ -z "$PASS" ] || [ -z "$PASS2" ]; then
        warn "You cannot set an empty password!"
      elif [ "$PASS" = "$PASS2" ]; then
        break
      else
        warn "The passwords do not match! Please try again"
      fi
    done
    HASH=$(echo -n "$PASS" | mkpasswd --method=SHA-512 --stdin)
    clear && printf '\n'

    ### Prompt for time zone
    while true; do
      TMZN=$(timedatectl list-timezones | gum choose --ordered --height=30 --limit=1 \
        --header="Select your time zone:"
      )
      if [ -z "$TMZN" ]; then
        warn "A time zone must be selected!"
      else
        break
      fi
    done
    clear && printf '\n'

    ### Display & confirm user settings or quit
    gum style --foreground="$GREEN" \
      "The following is a summary of your settings; please confirm everything looks correct:" && printf '\n'
    echo "$(gum style "     Disk:") $(gum style --foreground="$BLUE" "$DISK")"
    echo "$(gum style " Hostname:") $(gum style --foreground="$BLUE" "$HOST")"
    echo "$(gum style "     User:") $(gum style --foreground="$BLUE" "$USER")"
    echo "$(gum style "Time Zone:") $(gum style --foreground="$BLUE" "$TMZN")" && printf '\n'
    if gum confirm --default=false \
      --affirmative="Install" \
      --negative="Quit" \
      "Are you ready to proceed with installation?";
    then
      clear && printf '\n'
    else
      error "Installation cancelled."
      exit 0
    fi

    ###
    ### GENERATE FILES / FORMAT DISK
    ###
    ### Create /tmp directory
    NIXDIR=$(mktemp -d -t nixos-XXXXX)

    ### Clone git repo into /tmp for disko & create new git branch
    if ! gum spin \
      --title "Cloning Git repo..." \
      -- git clone https://github.com/j-pap/nixelOS.git "$NIXDIR";
    then
      error "Failed to clone Git repository!"
      exit 1
    fi
    cd "$NIXDIR"
    gum spin --show-error \
      --title "Creating new Git branch..." \
      -- git switch -c deployment

    ### Generate .nix configuration files
    gum spin --show-error \
      --title "Generating NixOS configuration files..." \
      -- nixos-generate-config --no-filesystems --dir "$NIXDIR"

    ### Copy system.stateVersion to hardware-configuration.nix
    STATE=$(grep "system.stateVersion = *" "$NIXDIR"/configuration.nix | sed 's/ #.*//')
    sed -i "$ i\\\n$STATE" "$NIXDIR"/hardware-configuration.nix

    ### ...and then move / remove respective generated .nix config files
    mkdir -p "$NIXDIR"/host
    mv "$NIXDIR"/hardware-configuration.nix "$NIXDIR"/host/hardware-configuration.nix
    rm -f "$NIXDIR"/configuration.nix

    ### Calculate & round the amount of system RAM for swap
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
    if gum spin --show-error \
      --title "Formatting & mounting disk..." \
      -- disko --mode disko --flake "$NIXDIR"#nixel;
    then
      gum style --foreground="$GREEN" \
        "Formatting complete!"
    else
      error "Formatting failed! Please try again"
      exit 1
    fi

    ### Calculate swap offset post-formatting & insert into variables.nix
    OFFSET=$(btrfs inspect-internal map-swapfile -r /mnt/.swap/swapfile)
    sed -i "9s/\".*\"/\"$OFFSET\"/" "$NIXDIR"/host/variables.nix

    ### Update flake.lock
    gum spin --show-error \
      --title "Updating flake.lock..." \
      -- nix flake update --refresh --extra-experimental-features 'nix-command flakes'

    ### Copy repo from /tmp to formatted install disk
    mkdir -p /mnt/etc/nixos && cd "$_"
    cp -ar "$NIXDIR"/. /mnt/etc/nixos

    ### Commit generated .nix files so they build with install
    git add /mnt/etc/nixos
    { git \
      -c user.email="nixel@null.local" \
      -c user.name="nixel" \
      commit -m "Commit .nix files generated @ install" > /dev/null;
    } 2>&1
    clear && printf '\n'

    ###
    ### INSTALLATION / FINALIZATION
    ###
    ### NixOS installation
    gum style --foreground="$BLUE" \
      "Performing installation, please be patient..."
    printf '\n'
    if ! nixos-install --no-root-passwd --flake /mnt/etc/nixos#nixel; then
      error "Installation failed! Please try again"
      exit 1
    fi

    ### Create XDG directories
    install -d -m 755 -o 1000 -g 100 \
      /mnt/home/"$USER"/{.config/cinnamon/backgrounds,Desktop,Documents,Downloads,Music,Pictures,Videos}

    ### Create Cinnamon desktop background source directory list
    chown -R 1000:100 /mnt/home/"$USER"/.config/
    install -m 755 -o 1000 -g 100 <(cat << EOF
    /home/$USER/Pictures
    /run/current-system/sw/share/backgrounds/gnome
    /run/current-system/sw/share/backgrounds/nixos
    EOF
    ) /mnt/home/"$USER"/.config/cinnamon/backgrounds/user-folders.lst

    ### Create post-install snapshots for potential powerwashing
    gum spin \
      --title "Taking snapshot of /home..." \
      -- btrfs subvolume snapshot -r /mnt/home /mnt/.snapshots/home-snap > /dev/null
    gum spin \
      --title "Taking snapshot of /var..." \
      -- btrfs subvolume snapshot -r /mnt/var /mnt/.snapshots/var-snap > /dev/null
    printf '\n'

    gum style --foreground="$GREEN" \
      "Installation complete! Please reboot when ready"
  '';
}
