{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.synit;
in
{
  config.system.build = lib.mkIf cfg.enable {
    bootStage2 = pkgs.replaceVarsWith {
      src = ./stage-2-init.sh;
      isExecutable = true;
      replacements = {
        shell = "${pkgs.bash}/bin/bash";
        systemConfig = null; # replaced in ../activation/top-level.nix
        synitPid1 = lib.getExe cfg.pid1.package;
        synitPid1Args = lib.escapeShellArgs (
          cfg.pid2.logger
          ++ [
            (lib.getExe cfg.syndicate-server.package)
            "--inferior"
            "--config"
            "${./config}/boot"
          ]
        );
        inherit (config.boot) readOnlyNixStore;
        inherit (config.system.nixos) distroName;
        path = lib.makeBinPath [
          pkgs.coreutils
          pkgs.util-linux
        ];
        postBootCommands = pkgs.writeText "local-cmds" ''
          ${config.boot.postBootCommands}
          ${config.powerManagement.powerUpCommands}
        '';
      };

      shell = "${pkgs.bash}/bin/bash";
      systemConfig = null; # replaced in ../activation/top-level.nix
      inherit (config.boot) readOnlyNixStore systemdExecutable;
      inherit (config.system.nixos) distroName;
      inherit (config.system.build) earlyMountScript;
      path = lib.makeBinPath [
        pkgs.coreutils
        pkgs.util-linux
      ];
      postBootCommands = pkgs.writeText "local-cmds" ''
        ${config.boot.postBootCommands}
        ${config.powerManagement.powerUpCommands}
      '';
    };
  };
}
