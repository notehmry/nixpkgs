{ lib, pkgs }:

{ ... }@args:
let
  toPreserves = lib.generators.toPreserves args;
  literal =
    with lib.types;
    nullOr (oneOf [
      bool
      int
      float
      str
      (attrsOf literal)
      (listOf literal)
    ])
    // {
      description = "Preserves value";
    };
  convert =
    syntax: name: value:
    pkgs.writeTextFile {
      inherit name;
      text = toString (map toPreserves value);
      checkPhase = ''
        ${lib.getExe pkgs.preserves-tools} convert \
          --output-format ${syntax} \
          <$target >tmp.pr && mv tmp.pr $target
      '';
    };
in
{
  inherit literal;
  type = lib.types.listOf literal;
  generate = name: value: (convert "text" name value) // { binary = convert "binary" name value; inherit value; };
}
