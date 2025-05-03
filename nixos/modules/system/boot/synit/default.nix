{
  lib,
  config,
  pkgs,
  utils,
  ...
}:

let
  inherit (lib)
    getExe
    literalMD
    mkDefault
    mkEnableOption
    mkPackageOption
    mkIf
    mkOption
    types
    ;

  inherit (utils) makeLogger;

  cfg = config.synit;
  mkIfSynit = mkIf cfg.enable;

in
{
  imports = [
    ./daemons.nix
    ./filesystems.nix
    ./logging.nix
    ./mdevd.nix
    ./networking.nix
  ];

  options.synit = {
    enable = mkEnableOption "Synit system layer";
    syndicate-server.package = mkPackageOption pkgs "syndicate-server" { };
    pid1.package = mkPackageOption pkgs "synit-pid1" { };
    pid1.args = mkOption {
      description = "The PID1 command line.";
      defaultText = literalMD "Attributes for `synit-pid`, `logger`, `syndicate-server`, and `syndicate-server-config`.";
      example = {
        control = {
          deps = [ "syndicate-server" ];
          text = [
            "--control"
          ];
        };
      };
      type = types.attrsOf (
        types.submodule {
          options = {
            deps = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "List of argument groups that must preceded this one.";
            };
            text = mkOption {
              type = types.uniq (types.listOf (types.either types.str types.path));
              description = "Group of arguments for the pid1 command-line.";
            };
          };
        }
      );
    };
  };

  config = mkIfSynit {
    assertions = [
      {
        assertion = !config.systemd.enable;
        message = "Synit and systemd cannot both be enabled";
      }
    ];

    environment.systemPackages = [
      cfg.syndicate-server.package
      pkgs.synit-service
    ];

    synit.pid1.args = {
      synit-pid1 = {
        text = mkDefault [ (getExe cfg.pid1.package) ];
      };
      logger = {
        deps = [ "synit-pid1" ];
        text = mkDefault [ (makeLogger [ ] "/var/log/synit") ];
      };
      syndicate-server = {
        deps = [ "logger" ];
        text = mkDefault [
          (getExe cfg.syndicate-server.package)
          "--inferior"
        ];
      };
      syndicate-server-config = {
        deps = [ "syndicate-server" ];
        text = mkDefault [
          "--config"
          "${./config}/boot"
        ];
      };
    };

    system.activationScripts.synit-config = {
      deps = [ "specialfs" ];
      text = "install -m644 -d /run/etc/syndicate/{core,system,services}";
    };

    systemd.enable = false;
  };

  meta = {
    maintainers = with lib.maintainers; [ ehmry ];
    # doc = ./todo.md;
  };
}
