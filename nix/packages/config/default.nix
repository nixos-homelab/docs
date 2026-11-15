{
  lib,
  writeText,
  stdenvNoCC,
  callPackage,
  docsLib,
  modules,
  additionalSettings ? { },
  # Current values of the options, for the cluster site (nix-docs `buildModuleDocsDir`)
  values ? null,
  ...
}:
let
  docsDir = stdenvNoCC.mkDerivation {
    name = "docs";
    buildInputs = [
    ];

    phases = [
      "buildPhase"
      "installPhase"
    ];

    buildPhase = ''
      runHook preBuild
      mkdir docs
      (
        cd docs
        ln -s ${../../../README.md} index.md
        ln -s ${docsLib.mkdocs.assets} nix-docs
        ${lib.join "\n" (
          lib.mapAttrsToList (name: module: ''
            ln -s ${
              let
                mpkgs = module.packages.${stdenvNoCC.hostPlatform.system};
              in
              callPackage docsLib.mkdocs.buildModuleDocsDir {
                options-docs = mpkgs.options-docs or null;
                lib-docs = mpkgs.lib-docs or null;
                manual-docs = mpkgs.manual-docs or null;
                inherit values;
              }
            } ${lib.removePrefix "homelab-" name}
          '') modules
        )}
      )
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      cp -r docs "$out"
      runHook postInstall
    '';
  };
in
writeText "mkdocs.yml" (
  builtins.toJSON (
    lib.recursiveUpdate (lib.recursiveUpdate {
      site_name = "NixOS Homelab";
      docs_dir = docsDir;
      theme = {
        name = "material";
        features = [
          "navigation.tabs"
          "navigation.instant"
          "navigation.sections"
          "content.code.copy"
          "search.highlight"
        ];
        palette = [
          {
            media = "(prefers-color-scheme: light)";
            scheme = "default";
            toggle = {
              icon = "material/brightness-7";
              name = "Dark mode";
            };
          }
          {
            media = "(prefers-color-scheme: dark)";
            scheme = "slate";
            toggle = {
              icon = "material/brightness-4";
              name = "Light mode";
            };
          }
        ];
      };
    } docsLib.mkdocs.settings) additionalSettings
  )
)
