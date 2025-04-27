{
  lib,
  stdenvNoCC,
  tclPackages,
  installShellFiles,
}:

stdenvNoCC.mkDerivation {
  pname = "synit-service";
  version = "1.0";

  dontUnpack = true;

  buildInputs = [ tclPackages.sycl ];
  nativeBuildInputs = [
    tclPackages.tcl.tclPackageHook
    installShellFiles
  ];

  installPhase = ''
    runHook preInstall
    install -m755 -D ${./service.tcl} $out/bin/service 
    installShellCompletion --fish --cmd service ${./completions.fish}
    runHook postInstall
  '';

  meta = {
    description = "Synit service management utility";
    maintainers = with lib.maintainers; [ ehmry ];
  };
}
