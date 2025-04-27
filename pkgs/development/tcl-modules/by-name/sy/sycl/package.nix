{
  lib,
  fetchFromGitea,
  buildNimSbom,
  tcl,
}:

buildNimSbom (_: {
  pname = "sycl";

  src = fetchFromGitea {
    domain = "git.syndicate-lang.org";
    owner = "ehmry";
    repo = "sycl";
    rev = "3ed22e4a6e51b59b81408e9f8b1eed6805f574b3";
    hash = "sha256-Qxvlv92STff1k2s1JfGhDIHh9KNyjf8kb3iL0zljW5M=";
  };

  nativeBuildInputs = [
    tcl.tclPackageHook
  ];
  buildInputs = [
    tcl
  ];

  installPhase = ''
    runHook preInstall
    install -D -t $out/lib/$name src/*.tcl libpreserves.so
    install -D -t $out/share/man/mann *.n.gz
    runHook postInstall
  '';

  meta = {
    description = "Syndicate Command Language";
    homepage = "https://git.syndicate-lang.org/ehmry/sycl";
    license = lib.licenses.unlicense;
    maintainers = with lib.maintainers; [ ehmry ];
  };
}) ./sbom.json
