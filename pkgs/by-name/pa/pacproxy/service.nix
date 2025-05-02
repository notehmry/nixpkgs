{
  lib,
  config,
  pkgs,
  ...
}:

let
  inherit (lib)
    getExe
    mkEnableOption
    mkIf
    mkOption
    mkPackageOption
    types
    ;

  cfg = config.pacproxy;
in
{
  _class = "service";
  options = {
    pacproxy = {
      enable = mkEnableOption "HTTP proxy server configured by a proxy auto-config (PAC) file.";
      package = mkPackageOption pkgs [ "pacproxy" ] { };
      pacFile = mkOption {
        type = types.path;
        description = "Path to a Proxy auto-config file.";
        example = "/etc/pac.js";
      };
      listen = {
        address = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "Address to bind to.";
        };
        port = mkOption {
          type = types.port;
          default = 8080;
          description = "TCP port to bind to.";
        };
      };
    };
  };

  config = {
    process = {
      executable = getExe cfg.package;
      args = [
        "-c"
        cfg.pacFile
        "-l"
        "${cfg.listen.address}:${toString cfg.listen.port}"
      ];
    };

    systemd.service = {
      after = [ "network.target" ];
      wants = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
    };
  };
}
