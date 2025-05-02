{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
}:

buildPythonPackage rec {
  pname = "preserves";
  version = "0.996.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-ydcndMjxqHX4/mxqdwxQ6NFSnG2ueUY2sUKQMPCz6ag=";
  };

  build-system = [
    setuptools
  ];

  meta = {
    description = "Preserves data language";
    homepage = "https://preserves.dev/python/";
    license = lib.licenses.apsl20;
    maintainers = with lib.maintainers; [ ehmry ];
  };
}
