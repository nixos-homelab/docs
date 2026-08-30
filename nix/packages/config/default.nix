{
  lib,
  writeText,
  stdenvNoCC,
  callPackage,
  docsLib,
  modules,
  additionalSettings ? { },
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
        ln -s ${../../../css} css
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
    {
      site_name = "NixOS Homelab";
      docs_dir = docsDir;
      extra_css = [ "css/extra.css" ];
    }
    // additionalSettings
  )
)
