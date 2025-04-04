{
  config,
  lib,
  pkgs,
  ...
}:

{
  config.system.build = lib.mkIf config.synit.enable {
    bootStage2 = pkgs.replaceVarsWith {
      src = ./stage-2-init.sh;
      isExecutable = true;
      replacements = {
        shell = "${pkgs.bash}/bin/bash";
        systemConfig = null; # replaced in ../activation/top-level.nix
        synit-pid1 = lib.getExe config.synit.pid1.package;
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
