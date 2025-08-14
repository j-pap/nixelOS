{
  config,
  lib,
  pkgs,
  inputs,
  vars,
  ...
}:
let
  # Find Flatpak package names: https://flathub.org/apps/search
  flatpak =
    let
      vlc = "org.videolan.VLC";
    in
    {
      # Auto-install the following Flatpaks:
      packages = [
        vlc
        "com.github.tchx84.Flatseal" # Flatpak permissions
        "org.libreoffice.LibreOffice"
        #"org.mozilla.firefox"
      ];

      # Create desktop shortcuts for the following Flatpaks:
      shortcuts = [
        #vlc
      ];
    };
in
{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
    ./variables.nix
  ];

  boot = {
    initrd.systemd.enable = true;
    extraModulePackages = builtins.attrValues {
      inherit (config.boot.kernelPackages)
        #kernelPkgName
      ;
    };
    kernelModules = [ ];
    kernelPackages = pkgs.linuxPackages_6_12;
    kernelParams = [
      "quiet"
    ];
    loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };
      systemd-boot = {
        enable = true;
        configurationLimit = 10;
        consoleMode = "auto";
        editor = false;
        memtest86.enable = true;
      };
      timeout = 5;
    };
    plymouth = {
      enable = true;
      theme = "bgrt";
      themePackages = [ pkgs.nixos-bgrt-plymouth ];
    };
    supportedFilesystems = [
      "btrfs"
    ];
    tmp.cleanOnBoot = true;
  };

  console.keyMap = "us";
  i18n.defaultLocale = "en_US.UTF-8";
  time.hardwareClockInLocalTime = true;

  environment = {
    cinnamon.excludePackages = [ ];
    pathsToLink = [
      "/share/backgrounds/gnome"
      "/share/backgrounds/nixos"
    ];
    shellAliases = {
      "nixel-rebuild" = "sudo nixos-rebuild switch --flake /etc/nixos#nixel";
    };
    systemPackages = builtins.attrValues {
      inherit (pkgs)
        dmidecode
        fastfetch
        firefox
        gnome-backgrounds
        gnome-software
        libnotify
        lshw
        nixos-wallpapers
        pciutils
        powerwash
        tldr
        tree
        usbutils
        variety
        vim
      ;
    };
  };

  hardware = {
    bluetooth = {
      enable = lib.mkDefault true;
      powerOnBoot = lib.mkDefault true;
    };
    enableAllFirmware = true;
    firmware = [ pkgs.linux-firmware ];
  };

  networking = {
    hostName = lib.mkDefault vars.host;
    networkmanager = {
      enable = lib.mkForce true;
      wifi.macAddress = "stable-ssid";
    };
  };
  systemd.services.NetworkManager-wait-online.enable = lib.mkDefault false;

  nix = {
    optimise.automatic = true;
    registry.nixpkgs.flake = inputs.nixpkgs;
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    settings = {
      auto-optimise-store = true;
      download-buffer-size = 536870912; # 512MB in Bytes
      experimental-features = [
        "flakes"
        "nix-command"
      ];
      max-jobs = 8;
      substituters = [
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
      trusted-users = [
        "@wheel"
      ];
      warn-dirty = false;
    };
  };

  nixpkgs = {
    config.allowUnfree = true;
    overlays = [
      (final: prev: {
        nixos-wallpapers = prev.symlinkJoin {
          name = "nixos-wallpapers";
          paths = builtins.filter lib.isDerivation (builtins.attrValues final.nixos-artwork.wallpapers);
        };
        powerwash = prev.callPackage ../pkgs/powerwash.nix { inherit config; };
      })
    ];
  };

  programs = {
    appimage = {
      enable = true;
      binfmt = true;
    };
    dconf.enable = true;
    git = {
      enable = true;
      package = pkgs.gitMinimal;
      prompt.enable = true;
      config = {
        safe = {
          directory = "/etc/nixos";
        };
        pull = {
          ff = "only";
        };
        user = {
          email = "nixel@null.local";
          name = "nixel";
        };
      };
    };
  };

  services = {
    btrfs.autoScrub.enable = true;
    fwupd.enable = true;
    printing.enable = true;

    flatpak = {
      enable = true;
      packages = flatpak.packages;
      remotes = [
        {
          name = "flathub";
          location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
        }
      ];
      uninstallUnmanaged = false;
      update.auto = {
        enable = true;
        onCalendar = "weekly";
      };
    };

    xserver = {
      enable = true;
      displayManager.lightdm.enable = true;
      desktopManager.cinnamon.enable = true;
    };
  };

  system.autoUpgrade = {
    enable = true;
    flake = "path:${inputs.self.outPath}#nixel";
    flags = [ ];
    operation = "switch";
    persistent = true;
    dates = "weekly";
    fixedRandomDelay = true;
    randomizedDelaySec = "30min";
    allowReboot = true;
    rebootWindow = {
      lower = "22:00";
      upper = "07:00";
    };
  };

  systemd = {
    services.nixos-upgrade.preStart =
      let
        date = lib.getExe' pkgs.coreutils "date";
        echo = lib.getExe' pkgs.coreutils "echo";
        git = lib.getExe' config.programs.git.package "git";
        nix = lib.getExe' config.nix.package "nix";
      in
      ''
        timestamp=$(${date} "+%Y/%m/%d %R")
        cd /etc/nixos

        ${echo} "### Resetting local branch changes..."
        ${git} reset --hard
        ${git} clean -dfx

        ${echo} "### Switching to 'main' branch..."
        ${git} switch main
        ${echo} "### Updating 'main' branch..."
        ${git} pull
        ${echo} "### Switching to 'deployment' branch..."
        ${git} switch deployment
        ${echo} "### Merging 'main' branch into 'deployment'..."
        ${git} merge -m "Merge upstream updates from branch 'main' into 'deployment' - $timestamp" main

        ${echo} "### Updating flake.lock..."
        ${nix} flake update

        if [ `git status --porcelain=1 | wc -l` -ne 0 ]; then
          ${echo} "### Committing changes detected in flake.lock"
          ${git} add flake.lock
          ${git} commit -m "flake.lock updated - $timestamp"
        else
          ${echo} "### No changes detected in flake.lock"
        fi

        ${echo} "### Starting NixOS upgrade..."
      '';

    user.services.desktop-shortcuts = {
      enable = lib.mkIf (lib.length flatpak.shortcuts > 0) true;
      description = "Softlink specified Flatpak shortcuts to the user's desktop";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "desktop-shortcuts" (
          lib.concatLines (
            builtins.map (
              app:
              let
                appName = lib.last (lib.splitString "." app);
              in
              "${lib.getExe' pkgs.coreutils "ln"} -s -f /var/lib/flatpak/exports/share/applications/${app}.desktop /home/${vars.user}/Desktop/${appName}.desktop"
            ) flatpak.shortcuts
          )
        );
      };
    };
  };

  users.users = {
    ${vars.user} = {
      description = lib.toSentenceCase vars.user;
      extraGroups = [
        "audio"
        "input"
        "networkmanager"
        "video"
        "wheel"
      ];
      initialHashedPassword = vars.pass;
      isNormalUser = true;
    };
    root.initialHashedPassword = "!"; # Disables root login
  };

  xdg.portal = {
    config.common.default = "gtk";
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
}
