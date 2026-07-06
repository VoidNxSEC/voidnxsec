{ ... }:
# disko declarative disk layout — server
# GPT 5-partition layout mirroring modules/01-partitioning.sh
# Upgrade: all LUKS2/Argon2id (was LUKS1/PBKDF2 in Void installer)
#
# IMPORTANT: disko iterates partitions in ASCII alphabetical order.
# Uppercase letters (A-Z, 65-90) sort before lowercase (a-z, 97-122).
# Physical order: ESP → boot → cryptswap → root → storage
# Alphabetical order: ESP('E') < boot('b') < cryptswap('c') < root('r') < storage('s')
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        # 1st: EFI system partition
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot/efi";
            mountOptions = [ "nodev" "nosuid" "noexec" "umask=0077" ];
          };
        };

        # 2nd: /boot (ext4, unencrypted — contains signed kernels for Lanzaboote)
        boot = {
          size = "1G";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/boot";
            mountOptions = [ "nodev" "nosuid" "noexec" ];
          };
        };

        # 3rd: Swap — LUKS2/Argon2id ('c' sorts before 'r')
        cryptswap = {
          size = "8G";
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
              "--pbkdf-memory" "1048576"
              "--pbkdf-parallel" "4"
              "--pbkdf-force-iterations" "3"
            ];
            content = {
              type = "swap";
            };
          };
        };

        # 4th: Root — LUKS2/Argon2id → /persist (impermanence: / is tmpfs)
        root = {
          size = "60G";
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

        # 5th: Data storage — LUKS2/Argon2id, takes all remaining space
        # ('s' sorts last → safe to use size = "100%")
        storage = {
          size = "100%";
          content = {
            type = "luks";
            name = "data_crypt";
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
              mountpoint = "/data";
              mountOptions = [ "nodev" "nosuid" ];
            };
          };
        };
      };
    };
  };
}
