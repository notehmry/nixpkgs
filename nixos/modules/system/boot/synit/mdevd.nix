{
  lib,
  config,
  pkgs,
  ...
}:

{
  config = lib.mkIf config.synit.enable {

    environment.etc = lib.mkIf config.boot.modprobeConfig.enable {
      # We don't place this into `extraModprobeConfig` so that stage-1 ramdisk doesn't bloat.
      "modprobe.d/firmware.conf".text =
        "options firmware_class path=${config.hardware.firmware}/lib/firmware";
    };

    synit.core.daemons.mdevd = {
      logging.enable = true;
      argv = [
        (lib.getExe pkgs.mdevd)
        "-v"
        "2"
        "-f"
        ./mdev.conf
        "-C"
      ];
      path = [
        pkgs.kmod
        pkgs.coreutils
      ];
    };

    system.activationScripts.mdevd = lib.mkIf config.boot.kernel.enable ''
      # The deprecated hotplug uevent helper is not used anymore
      if [ -e /proc/sys/kernel/hotplug ]; then
        echo "" > /proc/sys/kernel/hotplug
      fi

      # Allow the kernel to find our firmware.
      if [ -e /sys/module/firmware_class/parameters/path ]; then
        echo -n "${config.hardware.firmware}/lib/firmware" > /sys/module/firmware_class/parameters/path
      fi
    '';
  };
}
