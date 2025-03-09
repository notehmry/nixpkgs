{
  lib,
  buildNimPackage,
  fetchFromGitHub,
  openssl,
  sqlite,
}:

buildNimPackage (finalAttrs: {
  pname = "torrentinim";
  version = "0.9.1";

  src = fetchFromGitHub {
    owner = "sergiotapia";
    repo = "torrentinim";
    tag = "v${finalAttrs.version}";
    hash = "sha256-7GfcnwJ42oyhhGXrEbjHfrZqxt1AyYLTTHQee1YngNA=";
  };

  lockFile = ./lock.json;

  buildInputs = [
    openssl
    sqlite
  ];

  # Remove upstream linking configuration.
  postPatch = "rm nim.cfg";

  nimFlags = [
    "-d:ssl"
    "-d:usestd"
    "--path:${
      fetchFromGitHub {
        owner = "nitely";
        repo = "nim-regex";
        tag = "v0.26.0";
        hash = "sha256-5YjPkUZc1Xho1KAqH1BamZEuL7SRKtQ5aKuixA+cDCM=";
      }
    }/src"
    "--path:${
      fetchFromGitHub {
        owner = "nim-lang";
        repo = "db_connector";
        rev = "74aef399e5c232f95c9fc5c987cebac846f09d62";
        hash = "sha256-t8lsDSUiQ1jOwgfhrfV/NDlzG9lSyucthcb/QBrmlUY=";
      }
    }/src/db_connector"
  ];

  meta = {
    homepage = "https://github.com/sergiotapia/torrentinim";
    description = "torrent search engine and crawler";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      ehmry
    ];
    mainProgram = "torrentinim";
  };
})
