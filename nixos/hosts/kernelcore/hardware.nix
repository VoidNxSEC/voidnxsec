{ config, lib, modulesPath, ... }:
# Real hardware: Acer laptop — Intel Core (VMD) + NVIDIA RTX 3050 6GB
# NVMe ~477GB — LUKS1 root (migration to LUKS2/disko planned in Phase 4)
# Generated from: nixos-generate-config on kernelcore host
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "thunderbolt"
    "vmd"       # Intel Volume Management Device (required for NVMe on this board)
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ "dm-crypt" ];
  boot.kernelModules = [
    "kvm-intel"
    "nvidia"
    "nvidia_modeset"
    "nvidia_uvm"
    "nvidia_drm"
  ];
  boot.extraModulePackages = [ ];

  # Root — LUKS1 (UUID of the LUKS container, not the inner ext4)
  boot.initrd.luks.devices."luks-49aa90f9-15d5-4622-a2e6-02a989ecc7e3".device =
    "/dev/disk/by-uuid/49aa90f9-15d5-4622-a2e6-02a989ecc7e3";

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/feb9ea42-3b7c-460a-8e89-eae3e42f2436";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/B0B4-5BCD";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # Swap disk partition disabled — using ZRAM only (see profile.nix)
  # Partition /dev/disk/by-uuid/10b6cfb6-c7db-435f-8f63-7baa85e26004 reserved for Phase 4 (LUKS2)
  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # NVIDIA + firmware are unfree
  nixpkgs.config.allowUnfree = true;
}
