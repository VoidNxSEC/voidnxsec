{ ... }:
# disko declarative disk layout — laptop (NVMe, 3-partition layout)
# Adapted to actual hardware: nvme0n1 476.9GB
# p1: 1GB EFI (doubles as /boot for Lanzaboote — no separate /boot partition)
# p2: ~467GB LUKS2/Argon2id → /persist (root is impermanence tmpfs)
# p3: ~8.8GB LUKS2/Argon2id → swap (note: <16GB RAM, no full hibernate)
# WARNING: disko WIPES the disk before applying this config
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        # EFI + /boot combined (1GB — sufficient for Lanzaboote signed images)
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            # Mount directly at /boot (not /boot/efi) — required for Lanzaboote
            mountpoint = "/boot";
            mountOptions = [ "nodev" "nosuid" "noexec" "umask=0077" ];
          };
        };

        # Main LUKS2 partition: root (impermanence) + /persist
        root = {
          size = "100%FREE";
          end = "-9G"; # reserve space for swap at end
          content = {
            type = "luks";
            name = "root_crypt";
            settings = {
              allowDiscards = false;
            };
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
              # /persist is the on-disk storage; / is tmpfs (impermanence)
              mountpoint = "/persist";
              mountOptions = [ "noatime" "nodiratime" ];
            };
          };
        };

        # Swap: 9GB LUKS2 (existing was 8.8GB — keep same size)
        # 9GB < 16GB RAM: partial hibernate only; useful as swap pressure relief
        swap = {
          size = "9G";
          content = {
            type = "luks";
            name = "swap_crypt";
            settings = {
              allowDiscards = false;
            };
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
              randomEncryption = false;
            };
          };
        };
      };
    };
  };
}
