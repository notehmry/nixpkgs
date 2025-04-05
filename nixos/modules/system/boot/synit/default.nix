{
  lib,
  config,
  pkgs,
  ...
}:

let
  inherit (lib) mkOption types;
  cfg = config.synit;
in
{
  options.synit = {
    enable = lib.mkEnableOption "Synit system layer";
    pid1.package = lib.mkPackageOption pkgs "synit-pid1" { };

    daemons = mkOption {
      description = ''
        Definitions of daemons to assert into the Synit configuration dataspace.";
      '';
      type = types.attrsOf (
        types.submodule {
          options = {
            argv = mkOption {
              description = ''
                Daemon command line.
                A string is executed in a shell whereas a list of strings is executed directly.
                See [
                  https://synit.org/book/operation/builtin/daemon.html
                ](https://synit.org/book/operation/builtin/daemon.html#adding-process-specifications-to-a-service).
              '';
              type = with types; either str (listOf str);
            };
            restart = mkOption {
              description = ''
                Daemon restart policy.
                See [
                  https://synit.org/book/operation/builtin/daemon.html
                ](https://synit.org/book/operation/builtin/daemon.html#whether-and-when-to-restart).
              '';
              type = types.enum [
                "always"
                "on-error"
                "all"
                "never"
              ];
              default = "always";
            };
          };
        }
      );
    };

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

    /*
      systemd.package = pkgs.systemd.overrideAttrs (
        { meta, ... }:
        {
          meta = meta // {
            broken = true;
          };
        }
      );
    */

  };

  meta = {
    maintainers = with lib.maintainers; [ ehmry ];
    # doc = ./todo.md;
  };
}
