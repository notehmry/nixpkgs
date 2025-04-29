{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.networking;
  inherit (lib)
    mapAttrs'
    optionalAttrs
    ;

  preserves = pkgs.formats.preserves {
    ignoreNulls = true;
    rawStrings = true;
  };
  writePreservesFile = preserves.generate;

  quoteStrings =
    let
      __toPreserves = lib.generators.toPreserves {
        ignoreNulls = true;
        rawStrings = false;
      };
    in
    attrs: attrs // { inherit __toPreserves; };

  assertRecord = label: face: family: attrs: [
    face
    family
    (quoteStrings attrs)
    { _record = label; }
  ];

  mkInterfaceFile = face: cfg: {
    name = "syndicate/network/interface-${face}.pr";
    value.source = writePreservesFile "interface-${face}.pr" (
      [
        [
          cfg.name
          (
            quoteStrings {
              inherit (cfg)
                macAddress
                mtu
                tempAddress
                useDHCP
                ;
              proxyARP = if cfg.proxyARP then true else null;
            }
            // optionalAttrs cfg.wakeOnLan.enable { wakeOnLan.policy = cfg.wakeOnLan.policy; }
            // optionalAttrs cfg.virtual {
              owner = cfg.virtualOwner;
              type = cfg.virtualType;
            }
          )
          { _record = "interface"; }
        ]
      ]
      ++ map (assertRecord "addr" cfg.name "ipv4") cfg.ipv4.addresses
      ++ map (assertRecord "addr" cfg.name "ipv6") cfg.ipv6.addresses
      ++ map (assertRecord "route" cfg.name "ipv4") cfg.ipv4.routes
      ++ map (assertRecord "route" cfg.name "ipv6") cfg.ipv6.routes
    );
  };
in
{
  config = lib.mkIf config.synit.enable {
    environment.etc = mapAttrs' mkInterfaceFile cfg.interfaces;
    synit.core.daemons.static-network =
      let
        inherit (pkgs.tclPackages) tcl sycl;
      in
      {
        argv = [
          (lib.getExe' tcl "tclsh")
          ./networking.tcl
        ];
        env.TCLLIBPATH = "${sycl}/lib/${sycl.name}";
        protocol = "text/syndicate";
      };
  };
}
