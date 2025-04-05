{
  lib,
  config,
  pkgs,
  ...
}:

let
  inherit (lib) mkOption types;
  format = pkgs.formats.preserves {
    ignoreNulls = true;
    rawStrings = true;
  };
  writePreservesFile = format.generate;
  cfg = config.synit;
  mkIfSynit = lib.mkIf cfg.enable;
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
              type = with types; either str (listOf (either str path));
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

  config = {
    assertions = mkIfSynit [
      {
        assertion = !config.systemd.enable;
        message = "Synit and systemd cannot both be enabled";
      }
    ];

    environment.systemPackages = mkIfSynit (
      builtins.attrValues {
        inherit (pkgs) syndicate-server;
        synit-log = pkgs.writeScriptBin "synit-log" ''
          #!${lib.getExe pkgs.execline} -S0
          ${pkgs.s6}/bin/s6-log t /var/log/synit
        '';
      }
    );

    systemd.enable = mkIfSynit false;

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

    system.build.synitDaemons = writePreservesFile "daemons.pr" (
      lib.mapAttrsToList (name: attrs: [
        name
        (attrs // {
          argv = builtins.toJSON attrs.argv;
          env = if attrs.env == null then null else lib.mapAttrs builtins.toJSON attrs.env;
        })
        { _record = "daemon"; }
      ]) config.synit.daemons
    );
  };

  meta = {
    maintainers = with lib.maintainers; [ ehmry ];
    # doc = ./todo.md;
  };
}
