{ ... }:
# disko declarative disk layout — laptop (NVMe, 3-partition layout)
# Adapted to actual hardware: nvme0n1 476.9GB
#
# IMPORTANT: disko iterates partitions in ASCII alphabetical order.
# Uppercase (A-Z, 65-90) before lowercase (a-z, 97-122).
# Physical order: ESP(1G) → cryptswap(9G) → root(~466G)
# Alphabetical:   ESP('E'=69) < cryptswap('c'=99) < root('r'=114)
# root is LAST → safe to use size = "100%" (takes all remaining space)
#
# WARNING: disko WIPES the disk before applying this config
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        # 1st: EFI + /boot combined (1GB — sufficient for Lanzaboote signed images)
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            # Mount directly at /boot (not /boot/efi) — required for Lanzaboote on laptop
            mountpoint = "/boot";
            mountOptions = [ "nodev" "nosuid" "noexec" "umask=0077" ];
          };
        };

        # 2nd: Swap — LUKS2/Argon2id
        # 'c' < 'r' alphabetically → allocated before root, enabling root to use 100%
        # 9GB < 16GB RAM: partial swap pressure relief; no full hibernate possible
        cryptswap = {
          size = "9G";
          content = {
            type = "luks";
            name = "swap_crypt";
            settings.allowDiscards = false;
            passwordFile = "/tmp/luks-pass";
            extraFormatArgs = [
              "--type" "luks2"
              "--cipher" "aes-xts-plain64"
              "--key-size" "512"
              "--hash" "sha512"
              "--pbkdf" "argon2id"
              "--pbkdf-memory" "524288"
              "--pbkdf-parallel" "4"
              "--pbkdf-force-iterations" "3"
            ];
            content = {
              type = "swap";
            };
          };
        };

        # 3rd: Root — LUKS2/Argon2id → /persist (/ is impermanence tmpfs)
        # size = "100%" is safe here because root is the LAST partition (alphabetically)
        root = {
          size = "100%";
          content = {
            type = "luks";
            name = "root_crypt";
            settings.allowDiscards = false;
            passwordFile = "/tmp/luks-pass";
            extraFormatArgs = [
              "--type" "luks2"
              "--cipher" "aes-xts-plain64"
              "--key-size" "512"
              "--hash" "sha512"
              "--pbkdf" "argon2id"
              "--pbkdf-memory" "1048576"
              "--pbkdf-parallel" "4"
              "--pbkdf-force-iterations" "3"
            ];
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/persist";
              mountOptions = [ "noatime" "nodiratime" ];
            };
          };
        };
      };
    };
  };
}
