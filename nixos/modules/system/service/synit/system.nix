{
  lib,
  config,
  options,
  pkgs,
  ...
}:

let
  inherit (lib)
    attrNames
    types
    concatLists
    concatMapAttrs
    mapAttrs
    mapAttrsToList
    ;

  makeDaemonUpStates =
    prefixes: service:
    mapAttrsToList (
      name: module:
      let
        label = if name == "" then prefixes else prefixes ++ [ name ];
      in
      [
        [
          label
          { _record = "daemon"; }
        ]
        "up"
        { _record = "service-state"; }
      ]
    ) service.synit.daemons
    ++ builtins.attrValues (
      concatMapAttrs (
        subServiceName: subService: makeDaemons (prefixes ++ [ subServiceName ]) subService
      ) service.services
    );

  makeDaemons =
    prefixes: service:
    concatMapAttrs (
      name: module:
      let
        label = if name == "" then prefixes else prefixes ++ [ name ];
      in
      {
        "${lib.concatStringsSep "-" label}" =
          { ... }:
          {
            inherit label;
            imports = [ module ];
          };
      }
    ) service.synit.daemons
    // concatMapAttrs (
      subServiceName: subService: makeDaemons (prefixes ++ [ subServiceName ]) subService
    ) service.services;
in
{
  # Assert Synit services for those defined in isolation to the system.
  config = lib.mkIf config.synit.enable {

    synit.daemons = concatMapAttrs (
      serviceName: topLevelService: makeDaemons [ serviceName ] topLevelService
    ) config.system.services;
  };
}
