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
    pid1.package = lib.mkPackageOption pkgs "synit-pid1" { };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.systemd.enable;
        message = "Synit and systemd cannot both be enabled";
      }
    ];

    environment.systemPackages = builtins.attrValues {
      inherit (pkgs) syndicate-server;
      synit-log = pkgs.writeScriptBin "synit-log" ''
        #!${lib.getExe pkgs.execline} -S0
        ${pkgs.s6}/bin/s6-log t /var/log/synit
      '';
    };

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
