{ lib, modulesPath, ... }:
# Desktop hardware configuration — PLACEHOLDER
#
# TODO: Run on the desktop machine and paste output here:
#   sudo nixos-generate-config --show-hardware-config
#   lsblk -f
#   df -h
#
# Key info needed:
#   - Disk UUIDs (lsblk -f)
#   - CPU type (intel/amd → kvm-intel or kvm-amd)
#   - Available modules (nvme/sata/virtio)
#   - GPU if any
#   - Filesystem mount points
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # PLACEHOLDER — replace with actual kernel modules from nixos-generate-config
  boot.initrd.availableKernelModules = [
    "ahci" "xhci_pci" "nvme" "usb_storage" "sd_mod" "sr_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [
    "kvm-intel"   # TODO: change to kvm-amd if AMD CPU
  ];
  boot.extraModulePackages = [ ];

  # PLACEHOLDER — replace with actual UUIDs from: lsblk -f
  # fileSystems."/" = {
  #   device = "/dev/disk/by-uuid/REPLACE-WITH-ROOT-UUID";
  #   fsType = "ext4";
  # };
  # fileSystems."/boot" = {
  #   device = "/dev/disk/by-uuid/REPLACE-WITH-BOOT-UUID";
  #   fsType = "vfat";
  #   options = [ "fmask=0077" "dmask=0077" ];
  # };
  # swapDevices = [
  #   { device = "/dev/disk/by-uuid/REPLACE-WITH-SWAP-UUID"; }
  # ];

  # 1TB data disk for offload server (mount after confirming UUID)
  # fileSystems."/data" = {
  #   device = "/dev/disk/by-uuid/REPLACE-WITH-1TB-UUID";
  #   fsType = "ext4";
  #   options = [ "noatime" "nodiratime" ];
  # };

  networking.useDHCP = lib.mkDefault true;

  hardware.enableRedistributableFirmware = true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
