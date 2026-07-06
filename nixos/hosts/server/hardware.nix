{ modulesPath, ... }:
# Placeholder hardware config for server
# Replace with: nixos-generate-config --show-hardware-config
# or use nixos-anywhere which generates this automatically
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "ahci" "xhci_pci" "nvme" "usb_storage" "sd_mod" "sr_mod"
    "virtio_pci" "virtio_scsi" "virtio_blk" # VM support
  ];
  boot.initrd.kernelModules = [ "dm-snapshot" "dm-crypt" ];
  boot.kernelModules = [ "kvm-intel" "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # Server: ESP at /boot/efi, ext4 /boot is separate
  boot.loader.efi.efiSysMountPoint = "/boot/efi";

  nixpkgs.hostPlatform = "x86_64-linux";
}
