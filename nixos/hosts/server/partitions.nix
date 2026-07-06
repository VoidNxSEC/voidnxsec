{ ... }:
# disko declarative disk layout — server
# GPT 5-partition layout mirroring modules/01-partitioning.sh
# Upgrade: ROOT now LUKS2/Argon2id (was LUKS1/PBKDF2 in Void installer)
{
  disko.devices.disk.main = {
    type = "disk";
    # Override device per machine via --arg or hardware.nix
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot/efi";
            mountOptions = [ "nodev" "nosuid" "noexec" ];
          };
        };

        boot = {
          size = "1G";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/boot";
            mountOptions = [ "nodev" "nosuid" "noexec" ];
          };
        };

        swap = {
          size = "8G";
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
              "--pbkdf-memory" "1048576"
              "--pbkdf-parallel" "4"
              "--pbkdf-force-iterations" "3"
            ];
            content = {
              type = "swap";
              randomEncryption = false;
            };
          };
        };

        root = {
          size = "60G";
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
              # Actual / is tmpfs (impermanence); this becomes /persist
              mountpoint = "/persist";
              mountOptions = [ "noatime" "nodiratime" ];
            };
          };
        };

        data = {
          size = "100%";
          content = {
            type = "luks";
            name = "data_crypt";
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
              mountpoint = "/data";
              mountOptions = [ "nodev" "nosuid" ];
            };
          };
        };
      };
    };
  };
}
