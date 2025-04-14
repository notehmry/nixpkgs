{
  lib,
  config,
  pkgs,
  ...
}:

{
  config = lib.mkIf config.synit.enable {
    synit.core.daemons.syslog = {
      argv = [ (lib.getExe' pkgs.s6 "s6-socklog") ];
    };
  };
}
