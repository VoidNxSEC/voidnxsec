{ ... }:
# disko partition layout — NVMe ~477GB (Intel VMD → /dev/nvme0n1)
# LUKS2/Argon2id — no secretFile in initrd (losing the file = losing the disk).
# Primary unlock: passphrase. TPM2 can be added post-install as a convenience slot
# via systemd-cryptenroll (keeps passphrase as fallback).
# Destroys all existing partitions on first apply — fresh install only.
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/nvme0n1";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "fmask=0077" "dmask=0077" ];
            };
          };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              settings.allowDiscards = true;
              # LUKS2 default since cryptsetup ≥2.0; Argon2id > PBKDF2 (memory-hard)
              extraFormatArgs = [
                "--pbkdf" "argon2id"
                "--iter-time" "5000"
              ];
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                mountOptions = [ "defaults" "noatime" ];
              };
            };
          };
        };
      };
    };
  };
}
