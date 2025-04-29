{
  lib,
  fetchFromGitea,
  buildNimSbom,
  tcl,
}:

buildNimSbom {
  pname = "sycl";

  src = fetchFromGitea {
    domain = "git.syndicate-lang.org";
    owner = "ehmry";
    repo = "sycl";
    rev = "fb289108cdcdcf2b1dbdeddc36f266a53364c9f3";
    hash = "sha256-L9+EUsDiH7faGqp2TvHKe2MlOTlyK8fFnVntzP/PkeI=";
  };

  nativeBuildInputs = [
    tcl.tclPackageHook
  ];
  buildInputs = [
    tcl
  ];

  installPhase = ''
    runHook preInstall
    install -D -t $out/lib/$name src/*.tcl libdataspaces.so
    install -D -t $out/share/man/mann *.n.gz
    runHook postInstall
  '';

  meta = {
    description = "Syndicate Command Language";
    homepage = "https://git.syndicate-lang.org/ehmry/sycl";
    license = lib.licenses.unlicense;
    maintainers = with lib.maintainers; [ ehmry ];
  };
} ./sbom.json
