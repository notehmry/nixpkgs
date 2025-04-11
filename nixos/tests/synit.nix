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
            command = "${pkgs.greetd}/bin/agreety";
          };
        };
      };

      synit.enable = true;

      # virtualisation.graphics = false;
    };

  testScript = ''
    machine.succeed("poweroff")
  '';

  meta.maintainers = with lib.maintainers; [ ehmry ];
}
