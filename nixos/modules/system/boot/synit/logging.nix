{
  lib,
  config,
  pkgs,
  ...
}:

let
  preserves = pkgs.formats.preserves {
    ignoreNulls = true;
    rawStrings = true;
  };
in
{
  config = lib.mkIf config.synit.enable {
    environment.etc."syndicate/core/syslog.pr".source = preserves.generate "syslog.pr" [
      [
        [
          "s6-socklog"
          { _record = "daemon"; }
        ]
        { _record = "require-service"; }
      ]
      [
        "s6-socklog"
        { argv = [ (lib.getExe' pkgs.s6 "s6-socklog") ]; }
        { _record = "daemon"; }
      ]
    ];
  };
}
