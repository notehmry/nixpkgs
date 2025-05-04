{
  lib,
  config,
  pkgs,
  utils,
  ...
}:

let
  inherit (lib)
    literalMD
    makeBinPath
    mapAttrs
    mapAttrs'
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optionals
    optionalAttrs
    types
    ;
  inherit (utils) makeLogger;

  strOrPath = with types; either str path;

  preserves = pkgs.formats.preserves {
    ignoreNulls = true;
    rawStrings = true;
  };
  writePreservesFile = preserves.generate;

  cfg = config.synit;
  mkIfSynit = mkIf cfg.enable;

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
          default = true;
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
          defaultText = literalMD "{option}`config.security.wrapperDir` and GNU coreutils";
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
        logging = {
          enable = (mkEnableOption "inject a logging wrapper over this daemon") // {
            enable = true;
          };
          args = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = ''
              Command-line arguments passed to s6-log before the logging directory.
            '';
          };
          dir = mkOption {
            type = types.path;
            defaultText = literalMD "/var/log/${name}";
            default = "/var/log/${name}";
            description = ''
              Directory for log files from this daemon.
            '';
          };
        };
      };
    }
  );

  daemonToPreserves = attrs: [
    attrs.label
    {
      argv = builtins.toJSON (
        optionals attrs.logging.enable (
          makeLogger attrs.logging.args attrs.logging.dir
          ++ optionals (attrs.protocol == "none") [
            "fdmove"
            "-c"
            "1"
            "2"
          ]
        )
        ++ attrs.argv
      );
      env =
        let
          env' = optionalAttrs (attrs.env != null) attrs.env;
        in
        mapAttrs (_: v: if v == null then false else builtins.toJSON v) (
          (optionalAttrs (!attrs.clearEnv) config.systemd.globalEnvironment)
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

  requireDaemon =
    { label, ... }:
    [
      [
        label
        { _record = "daemon"; }
      ]
      { _record = "require-service"; }
    ];

in
{
  options.synit = {
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

    daemons = mkOption {
      description = ''
        Definitions of daemons to assert into the Synit configuration dataspace.";
      '';
      default = { };
      type = types.attrsOf daemonSubmodule;
    };

  };

  config = mkIfSynit {
    warnings = [
      "Synit daemons are using systemd.globalEnvironment until a portable option is introduced."
    ];

    environment.etc = mkMerge [
      (mapAttrs' (name: daemon: {
        name = "syndicate/core/daemon-${name}.pr";
        value.source = writePreservesFile "daemon-${name}.pr" [
          (requireDaemon daemon)
          (daemonToPreserves daemon)
        ];
      }) cfg.core.daemons)
      (mapAttrs' (name: daemon: {
        name = "syndicate/services/daemon-${name}.pr";
        value.source = writePreservesFile "daemon-${name}.pr" [
          (daemonToPreserves daemon)
        ];
      }) cfg.daemons)
      (
        with builtins;
        listToAttrs (
          map (
            name:
            let
              daemon = cfg.daemons.${name};
            in
            {
              name = "syndicate/services/require-${name}.pr";
              value.source = writePreservesFile "require-${name}.pr" [
                (requireDaemon daemon)
              ];
            }
          ) (filter (name: cfg.daemons.${name}.isRequired) (attrNames cfg.daemons))
        )
      )
    ];
  };

  meta = {
    maintainers = with lib.maintainers; [ ehmry ];
    # doc = ./todo.md;
  };
}
