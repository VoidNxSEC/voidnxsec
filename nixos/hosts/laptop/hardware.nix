{ modulesPath, ... }:
# Laptop hardware config (Acer, NVMe nvme0n1)
# Real disk UUIDs — update after nixos-generate-config if hardware differs
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci" "nvme" "usb_storage" "sd_mod"
    "thunderbolt" "vmd"
  ];
  boot.initrd.kernelModules = [ "dm-snapshot" "dm-crypt" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # Laptop: /boot is the EFI partition directly (no separate /boot)
  boot.loader.efi.efiSysMountPoint = "/boot";

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # Power management
  powerManagement.enable = true;
  powerManagement.cpuFreqGovernor = "powersave";

  nixpkgs.hostPlatform = "x86_64-linux";
}
