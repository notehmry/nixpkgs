{
  lib,
  rustPlatform,
  fetchFromGitea,
}:

rustPlatform.buildRustPackage rec {
  pname = "synit-pid1";
  version = "0.0.4";

  src = fetchFromGitea {
    domain = "git.syndicate-lang.org";
    owner = "synit";
    repo = "synit";
    rev = "51119bf1a5817360c6815cdc848f6b787f8f66e5";
    hash = "sha256-Y7T2nOOjAhFMooAwvyfY6+Pcnrw9gC+pwRot+2NQ8FI=";
  };
  cargoHash = "sha256-BmeNqUkzQb3kRqV7xasq+J3prFeeulM8hLJoRNC/7Pk=";
  useFetchCargoVendor = true;

  patchPhase =
    # Patch to take children and configuration from /run/booted-system.
    ''
      runHook prePatch
      substituteInPlace src/main.rs \
        --replace '"/usr/bin/syndicate-server"' '"/run/booted-system/sw/bin/syndicate-server"' \
        --replace '"/sbin/synit-log"' '"/run/booted-system/sw/bin/synit-log"' \
        --replace '"/etc/syndicate/boot"' '"/run/booted-system/etc/syndicate/boot"' \

      runHook postPatch
    '';

  sourceRoot = "source/${pname}";

  RUSTC_BOOTSTRAP = true;

  meta = {
    description = "Synit pid 1 program (patched for NixOS)";
    homepage = "https://synit.org/";
    license = lib.licenses.asl20;
    mainProgram = "synit-pid1";
    maintainers = with lib.maintainers; [ ehmry ];
  };
}
