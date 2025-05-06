{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.seatd;
  inherit (lib)
    getExe
    mkEnableOption
    mkIf
    mkOption
    mkPackageOption
    optional
    types
    ;
in
{
  meta.maintainers = with lib.maintainers; [ sinanmohd ];

  options.services.seatd = {
    enable = mkEnableOption "seatd";

    package = mkPackageOption pkgs [ "seatd" ] { };

    user = mkOption {
      type = types.str;
      default = "root";
      description = "User to own the seatd socket";
    };
    group = mkOption {
      type = types.str;
      default = "seat";
      description = "Group to own the seatd socket";
    };
    logLevel = mkOption {
      type = types.enum [
        "debug"
        "info"
        "error"
        "silent"
      ];
      default = "info";
      description = "Logging verbosity";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
    ] ++ optional config.systemd.enable pkgs.sdnotify-wrapper;
    users.groups.seat = mkIf (cfg.group == "seat") { };

    synit.depends = [
      {
        dependee.key = [
          "milestone"
          "login"
        ];
      }
      {
        key = [
          "milestone"
          "login"
        ];
        dependee.key = [
          "daemon"
          "seatd"
        ];
      }
    ];

    synit.daemons.seatd = {
      argv = [
        (getExe cfg.package)
        "-u"
        cfg.user
        "-g"
        cfg.group
      ];
    };

    systemd.services.seatd = {
      description = "Seat management daemon";
      documentation = [ "man:seatd(1)" ];

      wantedBy = [ "multi-user.target" ];
      restartIfChanged = false;

      serviceConfig = {
        Type = "notify";
        NotifyAccess = "all";
        SyslogIdentifier = "seatd";
        ExecStart = "${pkgs.sdnotify-wrapper}/bin/sdnotify-wrapper ${pkgs.seatd.bin}/bin/seatd -n 1 -u ${cfg.user} -g ${cfg.group} -l ${cfg.logLevel}";
        RestartSec = 1;
        Restart = "always";
      };
    };
  };
}
