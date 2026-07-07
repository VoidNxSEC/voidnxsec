{ lib, pkgs, config, ... }:
# NVIDIA RTX 3050 laptop (hybrid: Intel Xe iGPU + NVIDIA dGPU)
# Uses Prime offload mode — Intel handles display, NVIDIA on demand
#
# KNOWN ISSUE: finegrained power management disabled.
# Causes race condition with NVENC: GPU enters D3 before encoder cleanup → hang.
# Symptoms: system freeze when closing OBS. Only reboot recovers.
{
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = false;
    dynamicBoost.enable = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.production;
    forceFullCompositionPipeline = true;

    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true;
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  # xserver.videoDrivers required for nvidia-container-toolkit assertion,
  # even on Wayland (Hyprland). The NVIDIA module reads this to load the driver.
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia-container-toolkit.enable = true;

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      nvidia-vaapi-driver
      vulkan-loader
      vulkan-tools
    ];
  };

  # RTX 3050 6GB — keep VRAM allocator headroom
  boot.kernel.sysctl."vm.min_free_kbytes" = lib.mkDefault 65536;

  # Restrict GPU device access to nvidia group
  services.udev.extraRules = ''
    KERNEL=="nvidia[0-9]*", GROUP="nvidia", MODE="0660"
    KERNEL=="nvidiactl", GROUP="nvidia", MODE="0660"
    KERNEL=="nvidia-uvm", GROUP="nvidia", MODE="0660"
    KERNEL=="nvidia-uvm-tools", GROUP="nvidia", MODE="0660"
    KERNEL=="nvidia-modeset", GROUP="nvidia", MODE="0660"
  '';

  users.groups.nvidia = { };

  # CUDA cache in controlled location
  systemd.tmpfiles.rules = [
    "d /var/cache/cuda 0770 root nvidia -"
    "L+ /var/tmp/cuda-cache - - - - /var/cache/cuda"
  ];

  environment.systemPackages = with pkgs; [
    nvtopPackages.full
    nvitop
    cudaPackages.cudatoolkit
    nvidia-container-toolkit
  ];
}
