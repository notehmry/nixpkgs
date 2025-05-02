{
  lib,
  config,
  pkgs,
  ...
}:

{
  config = lib.mkIf config.synit.enable {
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
  };
}
