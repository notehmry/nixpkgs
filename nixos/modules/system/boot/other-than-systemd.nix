{
  config,
  lib,
  pkgs,
  ...
}:

{
  config = lib.mkIf (!config.systemd.enable) {

    warnings = lib.optional (pkgs.withSystemd ? true) {
      message = "pkgs.withSystemd is not set to false or nixpkgs.overaly is ineffective";
    };

    nixpkgs.overlays = [
      (
        final: prev:
        let
          deplatform =
            { overrideAttrs, ... }:
            overrideAttrs (
              { meta, ... }:
              {
                meta = meta // {
                  platforms = [ ];
                };
              }
            );
        in
        {
          enableSystemd = false;
          withSystemd = false;

          # systemd = null;
          udev = final.libudev-zero;
        }
      )
    ];

  };
}
