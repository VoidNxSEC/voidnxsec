{ config, lib, modulesPath, ... }:
# Real hardware: Acer laptop — Intel Core (VMD) + NVIDIA RTX 3050 6GB
# NVMe ~477GB — partition layout managed by disko (partitions.nix)
# filesystems + LUKS2 device declared there; kernel modules here.
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

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # NVIDIA + firmware are unfree
  nixpkgs.config.allowUnfree = true;
}
