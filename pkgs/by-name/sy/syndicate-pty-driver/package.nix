{
  lib,
  rustPlatform,
  fetchFromGitea,
}:

rustPlatform.buildRustPackage rec {
  pname = "syndicate-pty-driver";
  version = "0.1.1";

  src = fetchFromGitea {
    domain = "git.syndicate-lang.org";
    owner = "tonyg";
    repo = "syndicate-pty-driver";
    rev = "33ab20a4525e00c4f2fa4f825ed18835e7e2d008";
    hash = "sha256-emxYmjRWEumHgTkbbPL2sy4LvoEcxIjKjZDI7hnskgY=";
  };

  cargoHash = "sha256-vI+woKUlsGZPVzp3upt/z59B95xMpcI8WD91UdbHwHg=";
  useFetchCargoVendor = true;

  RUSTC_BOOTSTRAP = true;

  meta = {
    description = "Syndicate PTY (pseudoterminal) driver";
    homepage = "https://synit.org/";
    license = lib.licenses.asl20;
    mainProgram = "syndicate-pty-driver";
    maintainers = with lib.maintainers; [ ehmry ];
  };
}
