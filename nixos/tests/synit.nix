{ lib, ... }:
{
  name = "synit-stage1";

  nodes.machine =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      environment.etc."syndicate/services/greetd.pr".text = ''
        <require-service <daemon greetd-1>>
      '';

      services.greetd = {
        enable = true;
        vt = 1;
        settings = {
          default_session = {
            command = "${pkgs.greetd.greetd}/bin/agreety";
          };
        };
      };

      synit.enable = true;

      synit.pid1.args = [
        (lib.getExe config.synit.syndicate-server.package)
        "--inferior" "--config" "@systemConfig@/etc/syndicate/boot"
      ];

      # virtualisation.graphics = false;
    };

  testScript = ''
    machine.succeed("poweroff")
  '';

  meta.maintainers = with lib.maintainers; [ ehmry ];
}
