{
  lib,
  vars,
  ...
}:
{
  boot = {
    kernelParams = [ "resume_offset=${vars.swap.offset}" ];
    resumeDevice = "/dev/disk/by-label/nixelOS";
  };

  disko.devices.disk.main = {
    type = "disk";
    device = vars.disk;
    content = {
      type = "gpt";
      partitions = {
        BOOT = {
          size = "1M";
          type = "EF02";
        };

        ESP = {
          label = "boot";
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };

        ROOT = {
          label = "root";
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [
              "--force"
              "--label nixelOS"
            ];
            /*
            postCreateHook = let
              diskDev = config.disko.devices.disk.main.content.partitions.ROOT.device; # /dev/disk/by-partlabel/root
            in
            ''
              # Create empty snapshots of /home & /var for potential powerwashing
              MNT=$(mktemp -d -t btrfs-XXXXX)
              mount -o compress=zstd ${diskDev} "$MNT"
              trap 'cd /; umount "$MNT"; rm -rf "$MNT"' EXIT
              btrfs subvolume snapshot -r "$MNT"/@home "$MNT"/@snaps/home-blank
              btrfs subvolume snapshot -r "$MNT"/@var "$MNT"/@snaps/var-blank
            '';
            */
            subvolumes =
              let
                defaultOptions = [
                  "compress=zstd"
                  "discard=async"
                  "noatime"
                ];
              in
              {
                "@" = {
                  mountOptions = defaultOptions;
                  mountpoint = "/";
                };
                "@home" = {
                  mountOptions = lib.remove "noatime" defaultOptions;
                  mountpoint = "/home";
                };
                "@nix" = {
                  mountOptions = defaultOptions;
                  mountpoint = "/nix";
                };
                "@snaps" = {
                  mountOptions = defaultOptions;
                  mountpoint = "/.snapshots";
                };
                "@var" = {
                  mountOptions = defaultOptions;
                  mountpoint = "/var";
                };
                "@swap" = {
                  mountpoint = "/.swap";
                  swap.swapfile.size = vars.swap.size;
                };
              };
          };
        };
      };
    };
  };
}
