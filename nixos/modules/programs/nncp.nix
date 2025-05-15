{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  inherit (lib) concatMapStrings getExe;
  inherit (utils) writeExeclineScript;

  nncpCfgFile = "/run/nncp.hjson";
  programCfg = config.programs.nncp;
  settingsFormat = pkgs.formats.json { };
  jsonCfgFile = settingsFormat.generate "nncp.json" programCfg.settings;
  pkg = programCfg.package;

  configScript = writeExeclineScript "nncp-config.el" [ ] ''
    umask 127
    foreground { rm -f ${nncpCfgFile} }
    pipeline -r {
    ${concatMapStrings (f: ''
      foreground {
        redirfd -r 0 "${f}"
        ${getExe pkgs.hjson-go} -c
      }
    '') ([ jsonCfgFile ] ++ config.programs.nncp.secrets)}
    }
    foreground {
      redirfd -w 1 ${nncpCfgFile}
      ${getExe pkgs.jq} --slurp "reduce .[] as $x ({}; . * $x)"
    }
    chgrp ${programCfg.group} ${nncpCfgFile}
  '';
in
{
  options.programs.nncp = {

    enable = lib.mkEnableOption "NNCP (Node to Node copy) utilities and configuration";

    group = lib.mkOption {
      type = lib.types.str;
      default = "uucp";
      description = ''
        The group under which NNCP files shall be owned.
        Any member of this group may access the secret keys
        of this NNCP node.
      '';
    };

    package = lib.mkPackageOption pkgs "nncp" { };

    secrets = lib.mkOption {
      type = with lib.types; listOf str;
      example = [ "/run/keys/nncp.hjson" ];
      description = ''
        A list of paths to NNCP configuration files that should not be
        in the Nix store. These files are layered on top of the values at
        [](#opt-programs.nncp.settings).
      '';
    };

    settings = lib.mkOption {
      type = settingsFormat.type;
      description = ''
        NNCP configuration, see
        <http://www.nncpgo.org/Configuration.html>.
        At runtime these settings will be overlayed by the contents of
        [](#opt-programs.nncp.secrets) into the file
        `${nncpCfgFile}`. Node keypairs go in
        `secrets`, do not specify them in
        `settings` as they will be leaked into
        `/nix/store`!
      '';
      default = { };
    };

  };

  config = lib.mkIf programCfg.enable {

    environment = {
      systemPackages = [ pkg ];
      etc."nncp.hjson".source = nncpCfgFile;
    };

    programs.nncp.settings = {
      spool = lib.mkDefault "/var/spool/nncp";
      log = lib.mkDefault "/var/spool/nncp/log";
    };

    systemd.tmpfiles.settings.nncp =
      let
        rule.d = {
          mode = "0770";
          user = "root";
          inherit (programCfg) group;
        };
      in
      {
        ${programCfg.settings.spool} = rule;
        ${programCfg.settings.log} = rule;
      };

    systemd.services.nncp-config = {
      description = "Generate NNCP configuration";
      wantedBy = [ "basic.target" ];
      serviceConfig = {
        ExecStart = configScript;
        Type = "oneshot";
      };
    };

    synit.milestones.system.requires = [
      {
        key = [
          "milestone"
          "nncp"
        ];
      }
    ];

    synit.daemons.nncp-config = {
      argv = [ configScript ];
      restart = "on-error";
      logging.enable = false;
      provides = [
        [
          "milestone"
          "nncp"
        ]
      ];
    };
  };

  meta.maintainers = with lib.maintainers; [ ehmry ];
}
