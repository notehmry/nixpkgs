{
  lib,
  config,
  pkgs,
  ...
}:

let
  inherit (lib) mkOption types concatMap;
  preserves = pkgs.formats.preserves {
    ignoreNulls = true;
    rawStrings = true;
  };
  writePreservesFile = preserves.generate;

  cfg = config.synit;
  mkIfSynit = lib.mkIf cfg.enable;

  logWrapper = pkgs.writeTextFile {
    name = "system-bus.el";
    executable = true;
    text = ''
      #!${lib.getExe pkgs.execline} -s0
      fdreserve 2
      multisubstitute {
        importas logr FD0
        importas logw FD1
      }
      piperw $logr $logw
      background {
        fdmove 0 $logr
        ${pkgs.s6}/bin/s6-log /var/log/synit
      }
      fdmove 2 $logw
      $@
    '';
  };

in
{
  options.synit =
    let
      strOrPath = with types; either str path;
    in
    {
      enable = lib.mkEnableOption "Synit system layer";
      syndicate-server.package = lib.mkPackageOption pkgs "syndicate-server" { };
      pid1.package = lib.mkPackageOption pkgs "synit-pid1" { };
      pid1.args = lib.mkOption {
        type = types.listOf strOrPath;
        default = [
          logWrapper
          (lib.getExe cfg.syndicate-server.package)
          "--inferior"
          "--config"
          "@systemConfig@/etc/syndicate/boot"
        ];
        defaultText = lib.literalMD ''The `syndicate-server` wrapped by `s6-log`.'';
      };

      services = mkOption {
        description = ''
          Abstract Syndicate services representing NixOS services.
        '';
        type = types.attrsOf (
          types.submodule {
            options = {
              label = mkOption {
                type = preserves.literal;
              };
              dependsOn = mkOption {
                type = types.listOf preserves.literal;
              };
            };
          }
        );
      };

      daemons = mkOption {
        description = ''
          Definitions of daemons to assert into the Synit configuration dataspace.";
        '';
        type = types.attrsOf (
          types.submodule {
            options = {
              label = mkOption {
                type = with types; listOf str;
                description = ''
                  Label for daemon assertion - `<daemon @label [ … ]>`.
                  Using a list of symbols rather than a concatenated symbol allows patterns
                  to be built that match multiple daemons by prefix. *TODO: is this correct?*
                '';
              };
              argv = mkOption {
                description = ''
                  Daemon command line.
                  A string is executed in a shell whereas a list of strings is executed directly.
                  See [
                    https://synit.org/book/operation/builtin/daemon.html
                  ](https://synit.org/book/operation/builtin/daemon.html#adding-process-specifications-to-a-service).
                '';
                type = with types; either strOrPath (listOf strOrPath);
              };
              clearEnv = mkOption {
                description = ''
                  Whether the Unix process environment is cleared or inherited.
                  See [
                    https://synit.org/book/operation/builtin/daemon.html
                  ](https://synit.org/book/operation/builtin/daemon.html#specifying-subprocess-environment-variables).
                '';
                type = types.bool;
                default = false;
              };
              dir = mkOption {
                description = ''
                  Sets the working direcctory of a daemon.
                  See [
                    https://synit.org/book/operation/builtin/daemon.html
                  ](https://synit.org/book/operation/builtin/daemon.html#setting-the-current-working-directory-for-a-subprocess).
                '';
                type = with types; nullOr str;
                default = null;
              };
              env = mkOption {
                description = ''
                  Sets Unix process environment for a daemon.
                  See [
                    https://synit.org/book/operation/builtin/daemon.html
                  ](https://synit.org/book/operation/builtin/daemon.html#specifying-subprocess-environment-variables).
                '';
                type = with types; nullOr (attrsOf str);
                default = null;
              };
              protocol = mkOption {
                description = ''
                  Specify a protocol for communicating with a daemon over stdin and stdout.
                  See [
                    https://synit.org/book/operation/builtin/daemon.html
                  ](https://synit.org/book/operation/builtin/daemon.html#speaking-syndicate-network-protocol-via-stdinstdout).
                '';
                type = types.enum [
                  "none"
                  "application/syndicate"
                  "text/syndicate"
                ];
                default = "none";
              };
              readyOnStart = mkOption {
                description = ''
                  Whether a daemon should be considered ready immediately after startup.
                  See [
                    https://synit.org/book/operation/builtin/daemon.html
                  ](https://synit.org/book/operation/builtin/daemon.html#ready-signalling).
                '';
                type = types.bool;
                default = true;
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

  config = mkIfSynit {
    assertions = [
      {
        assertion = !config.systemd.enable;
        message = "Synit and systemd cannot both be enabled";
      }
    ];

    environment.systemPackages = [ cfg.syndicate-server.package ];

    environment.etc = {
      "syndicate/core/.keep".text = "";
      "syndicate/services/depends.pr".source = writePreservesFile "depends.pr" (
        concatMap (
          { label, dependsOn }:
          map (dependee: [
            [
              label
              { _record = "service"; }
            ]
            dependee
            { _record = "depends-on"; }
          ]) dependsOn
        ) (builtins.attrValues cfg.services)
      );
      "syndicate/services/daemons.pr".source = writePreservesFile "daemons.pr" (
        lib.mapAttrsToList (name: attrs: [
          name
          (
            attrs
            // {
              argv = builtins.toJSON attrs.argv;
              env = if attrs.env == null then null else lib.mapAttrs builtins.toJSON attrs.env;
            }
          )
          { _record = "daemon"; }
        ]) config.synit.daemons
      );
    };

    systemd.enable = false;
  };

  meta = {
    maintainers = with lib.maintainers; [ ehmry ];
    # doc = ./todo.md;
  };
}
