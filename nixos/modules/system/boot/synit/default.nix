{
  lib,
  config,
  pkgs,
  ...
}:

let
  inherit (lib) mkOption types;
  strOrPath = with types; either str path;
  format = pkgs.formats.preserves {
    ignoreNulls = true;
    rawStrings = true;
  };
  writePreservesFile = format.generate;

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
  options.synit = {
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

    environment.etc = {
      "syndicate/boot".source = ./boot;
      "syndicate/core".source = ./core;
    };

    environment.systemPackages = [ cfg.syndicate-server.package ];

    system.build.synitDaemons = writePreservesFile "daemons.pr" (
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

    system.activationScripts.synitRunConfig = lib.stringAfter [ "specialfs" ] ''
      install -v -m644 -d /run/etc/syndicate/{core,services}
      install -m644 -t /run/etc/syndicate/services ${config.system.build.synitDaemons}
    '';

    systemd.enable = false;
  };

  meta = {
    maintainers = with lib.maintainers; [ ehmry ];
    # doc = ./todo.md;
  };
}
