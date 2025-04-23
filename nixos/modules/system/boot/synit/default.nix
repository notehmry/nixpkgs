{
  lib,
  config,
  pkgs,
  utils,
  ...
}:

let
  inherit (lib)
    makeBinPath
    mapAttrs
    mapAttrs'
    mkMerge
    mkOption
    getExe
    types
    ;

  strOrPath = with types; either str path;

  preserves = pkgs.formats.preserves {
    ignoreNulls = true;
    rawStrings = true;
  };
  writePreservesFile = preserves.generate;

  cfg = config.synit;
  mkIfSynit = lib.mkIf cfg.enable;

  logWrapper = utils.writeExeclineScript "system-bus.el" "-s" ''
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

  daemonSubmodule = types.submodule (
    { name, ... }:
    {
      options = {
        label = mkOption {
          type = preserves.literal;
          default = name;
          description = ''
            Label for daemon assertion - `<daemon @label [ … ]>`.
            Using a list of symbols rather than a concatenated symbol allows patterns
            to be built that match multiple daemons by prefix. *TODO: is this correct?*
          '';
        };
        isRequired = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether this daemon is an explicitly required service.
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
            If this option is set then {option}`globalEnvironment`
            is not propagated to this daemon.
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
        path = mkOption {
          type =
            with types;
            listOf (oneOf [
              str
              path
              package
            ]);
          default = [ pkgs.coreutils ];
          defaultText = lib.literalMD "{option}`config.security.wrapperDir` and GNU coreutils";
          description = ''
            List of directories to compose into the PATH environmental variable.
          '';
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

  daemonToPreserves = attrs: [
    attrs.label
    {
      argv = builtins.toJSON attrs.argv;
      env =
        let
          env' = lib.optionalAttrs (attrs.env != null) attrs.env;
        in
        mapAttrs (_: v: if v == null then false else builtins.toJSON v) (
          (lib.optionalAttrs (!attrs.clearEnv) config.systemd.globalEnvironment)
          // env'
          // {
            PATH = env'.PATH or "${config.security.wrapperDir}:${makeBinPath attrs.path}";
          }
        );
      inherit (attrs)
        dir
        clearEnv
        readyOnStart
        restart
        protocol
        ;
    }
    { _record = "daemon"; }
  ];
in
{
  imports = [
    ./logging.nix
    ./mdevd.nix
    ./networking.nix
  ];

  options.synit = {
    enable = lib.mkEnableOption "Synit system layer";
    syndicate-server.package = lib.mkPackageOption pkgs "syndicate-server" { };
    pid1.package = lib.mkPackageOption pkgs "synit-pid1" { };
    pid2.logger = lib.mkOption {
      description = ''
        Wapper that captures stderr of PID2 for logging.
        An emptly list disables logging.
      '';
      type = with types; listOf strOrPath;
      default = [ logWrapper ];
      defaultText = lib.literalMD "`s6-log` logging to `/var/log/synit`";
    };

    core = {
      daemons = mkOption {
        description = ''
          Definitions of daemons to assert as Synit core services.
          For each daemon defined in core a `<requires-service <daemon ''${label}>>`
          assertion is also made.
        '';
        default = { };
        type = types.attrsOf daemonSubmodule;
      };
    };

    requires = mkOption {
      description = ''
        Services required by the top-level configuration.
        Each entry is the name of an attr in `config.synit.services`.
      '';
      type = with types; listOf str;
    };

    services = mkOption {
      description = ''
        Abstract Syndicate services representing NixOS services.
      '';
      default = { };
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              label = mkOption {
                description = "Label used in assertions to refer to this service.";
                type = preserves.literal;
                default = [
                  name
                  { _record = "service"; }
                ];
              };
              dependsOn = mkOption {
                description = "List of services-states that this service depends on.";
                type = types.listOf preserves.literal;
              };
            };
          }
        )
      );
    };

    daemons = mkOption {
      description = ''
        Definitions of daemons to assert into the Synit configuration dataspace.";
      '';
      default = { };
      type = types.attrsOf daemonSubmodule;
    };

  };

  config = mkIfSynit {
    assertions = [
      {
        assertion = !config.systemd.enable;
        message = "Synit and systemd cannot both be enabled";
      }
    ];

    warnings = [
      "Synit daemons are using systemd.globalEnvironment until a portable option is introduced."
    ];

    environment.systemPackages = [ cfg.syndicate-server.package ];

    environment.etc = mkMerge [
      (mapAttrs' (name: daemon: {
        name = "syndicate/core/daemon-${name}.pr";
        value.source = writePreservesFile "daemon-${name}.pr" [
          [
            [
              daemon.label
              { _record = "daemon"; }
            ]
            { _record = "require-service"; }
          ]
          (daemonToPreserves daemon)
        ];
      }) cfg.core.daemons)
      {
        "syndicate/services/daemons.pr".source = writePreservesFile "daemons.pr" (
          map daemonToPreserves (builtins.attrValues config.synit.daemons)
        );
      }
      (mapAttrs' (
        serviceName:
        { label, dependsOn }:
        {
          name = "syndicate/services/service-${serviceName}.pr";
          value.source = writePreservesFile "service-${serviceName}.pr" (
            [
              [
                label
                { _record = "require-service"; }
              ]
            ]
            ++ map (dependee: [
              label
              dependee
              { _record = "depends-on"; }
            ]) dependsOn
          );
        }
      ) cfg.services)
      (
        with builtins;
        listToAttrs (map (
          name:
          let
            daemon = cfg.daemons.${name};
          in
          {
            name = "syndicate/services/require-${name}.pr";
            value.source = writePreservesFile "require-${name}.pr" [
              [
                [
                  daemon.label
                  { _record = "daemon"; }
                ]
                { _record = "require-service"; }
              ]
            ];
          }
        ) (filter (name: cfg.daemons.${name}.isRequired) (attrNames cfg.daemons)))
      )
    ];

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
