{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  setuptools-scm,
  preserves,
}:

buildPythonPackage rec {
  pname = "syndicate-py";
  version = "0.19.1";
  pyproject = true;

  src = fetchPypi {
    pname = "syndicate_py";
    inherit version;
    hash = "sha256-NYIB886o/+An1e1cH65B7OxK8xgRWobyNz2o2cUcArw=";
  };

  build-system = [
    setuptools
    setuptools-scm
  ];

  dependencies = [
    preserves
  ];

  meta = {
    description = "Syndicated Actor Model";
    homepage = "https://git.syndicate-lang.org/syndicate-lang/syndicate-py";
    license = lib.licenses.gpl3Plus;
    maintainers = with lib.maintainers; [ ehmry ];
  };
}
