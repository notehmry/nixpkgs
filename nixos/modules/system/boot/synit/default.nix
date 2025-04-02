{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.synit;
in
{
  options.synit = {
    enable = lib.mkEnableOption "Synit system layer";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.systemd.enable;
        message = "Synit and systemd cannot both be enabled";
      }
    ];

    systemd.enable = false;
    systemd.package = pkgs.systemd.overrideAttrs (
      { meta, ... }:
      {
        meta = meta // {
          broken = true;
        };
      }
    );
  };

  meta = {
    maintainers = with lib.maintainers; [ ehmry ];
    doc = ./todo.md;
  };
}
