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
      synit.enable = true;
    };

  testScript = ''
    machine.wait_for_open_port(24)
    machine.succeed("poweroff")
  '';

  meta.maintainers = with lib.maintainers; [ ehmry ];
}
