{
  description = "homelab-docs";
  # The module repos share shared's versions of what they have in common, so two of them can't bring
  # two copies of one module into the same evaluation
  inputs = {
    systems.url = "github:nix-systems/default-linux";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell.url = "github:numtide/devshell";
    docs = {
      url = "github:andsens/nix-docs";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    homelab-shared = {
      url = "github:nixos-homelab/shared";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.docs.follows = "docs";
    };
    homelab-storage = {
      url = "github:nixos-homelab/storage";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.docs.follows = "docs";
      inputs.homelab-shared.follows = "homelab-shared";
      inputs.kube-generators.follows = "homelab-shared/kube-generators";
      inputs.setup-secrets.follows = "homelab-shared/setup-secrets";
    };
    homelab-media = {
      url = "github:nixos-homelab/media";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.docs.follows = "docs";
      inputs.homelab-shared.follows = "homelab-shared";
      inputs.kube-generators.follows = "homelab-shared/kube-generators";
      inputs.setup-secrets.follows = "homelab-shared/setup-secrets";
      inputs.homelab-networking.follows = "homelab-networking";
    };
    homelab-monitoring = {
      url = "github:nixos-homelab/monitoring";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.docs.follows = "docs";
      inputs.homelab-shared.follows = "homelab-shared";
      inputs.homelab-storage.follows = "homelab-storage";
      inputs.kube-generators.follows = "homelab-shared/kube-generators";
      inputs.setup-secrets.follows = "homelab-shared/setup-secrets";
    };
    homelab-finance = {
      url = "github:nixos-homelab/finance";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.docs.follows = "docs";
      inputs.homelab-shared.follows = "homelab-shared";
      inputs.homelab-storage.follows = "homelab-storage";
      inputs.kube-generators.follows = "homelab-shared/kube-generators";
      inputs.setup-secrets.follows = "homelab-shared/setup-secrets";
    };
    homelab-networking = {
      url = "github:nixos-homelab/networking";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.docs.follows = "docs";
      inputs.homelab-shared.follows = "homelab-shared";
      inputs.kube-generators.follows = "homelab-shared/kube-generators";
      inputs.nixhelm.follows = "homelab-shared/nixhelm";
      inputs.setup-secrets.follows = "homelab-shared/setup-secrets";
    };
    homelab-personal = {
      url = "github:nixos-homelab/personal";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.docs.follows = "docs";
      inputs.homelab-shared.follows = "homelab-shared";
      inputs.homelab-storage.follows = "homelab-storage";
      inputs.kube-generators.follows = "homelab-shared/kube-generators";
      inputs.setup-secrets.follows = "homelab-shared/setup-secrets";
    };
    homelab-development = {
      url = "github:nixos-homelab/development";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.docs.follows = "docs";
      inputs.homelab-shared.follows = "homelab-shared";
      inputs.kube-generators.follows = "homelab-shared/kube-generators";
      inputs.setup-secrets.follows = "homelab-shared/setup-secrets";
    };
  };

  outputs =
    {
      systems,
      flake-parts,
      nixpkgs,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (
      {
        flake-parts-lib,
        self,
        inputs,
        lib,
        ...
      }:
      {
        imports = [ inputs.devshell.flakeModule ];
        systems = import systems;
        flake =
          let
            modules = {
              inherit (inputs)
                homelab-shared
                homelab-storage
                homelab-media
                homelab-monitoring
                homelab-finance
                homelab-networking
                homelab-personal
                homelab-development
                ;
            };
          in
          {
            nixosModules.docs = flake-parts-lib.importApply ./nix/modules/docs { inherit self inputs; };
            lib = {
              /**
                The site: its mkdocs.yml (`config`) and the site built strict from it (`site`). `values` (option name
                to `{ value; changed; }`) adds the current values, `siteUrl` is where it is served.
              */
              site =
                {
                  pkgs,
                  values ? null,
                  siteUrl ? "https://nixos-homelab.github.io/",
                }:
                let
                  python = pkgs.python3.withPackages (p: [
                    p.mkdocs
                    p.mkdocs-material
                  ]);
                  config = pkgs.callPackage ./nix/packages/config {
                    docsLib = inputs.docs.lib;
                    inherit modules values;
                    additionalSettings = {
                      site_author = "Anders Ingemann";
                      site_url = siteUrl;
                      remote_branch = "main";
                    };
                  };
                in
                {
                  inherit config;
                  mkdocs = "${python}/bin/mkdocs";
                  site = pkgs.runCommand "site" { } ''
                    ${python}/bin/mkdocs build --strict --config-file ${config} --site-dir "$out"
                  '';
                };
              /**
                The options the site shows, by name, as `optionsNix` entries (`loc`, `type`, ...), from every repo's
                `options-docs`.
              */
              options =
                system:
                lib.foldl' (
                  acc: module:
                  let
                    docs = module.packages.${system}.options-docs or null;
                  in
                  if docs == null then
                    acc
                  else if docs ? prefixGroups then
                    lib.foldl' (a: group: a // group.nix) acc (lib.attrValues docs.prefixGroups)
                  else
                    acc // docs.nix
                ) { } (lib.attrValues modules);
            };
          };
        perSystem =
          {
            system,
            pkgs,
            lib,
            config,
            ...
          }:
          let
            inherit (self.lib.site { inherit pkgs; }) mkdocs;
          in
          {
            # Dead Nix code. Pattern names stay: modules take { config, lib, pkgs, ... } whether they use them or not
            checks = {
              deadnix = pkgs.runCommand "deadnix" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
                deadnix --fail --no-lambda-pattern-names ${self}
                touch $out
              '';
              # The site, built strict: broken links and missing pages fail the check
              site = config.packages.site;
            }
            // import ./nix/tests {
              inherit self inputs pkgs lib;
            };
            devshells = {
              default = {
                motd = "";
                commands = [
                  {
                    help = "Update flakes using local working copies";
                    name = "update-flakes";
                    command = ''
                      [[ $# -gt 0 ]] || { printf "Usage: update-flakes FLAKE...\n" >&2; exit 1; }
                      update_flakes=("$@")
                      args=()
                      for flake in "''${update_flakes[@]}"; do
                        args+=(--override-input "$flake" "git+file://$PWD/../$flake" "$flake")
                      done
                      exec ${lib.getExe pkgs.nix} flake update --allow-dirty-locks "''${args[@]}"
                    '';
                  }
                  {
                    help = "Run mkdocs";
                    name = "mkdocs";
                    command = ''
                      nix build '${./.}#config' -o mkdocs.yml
                      ${mkdocs} "$@"
                    '';
                  }
                ];
              };
            };
            apps.mkdocs = {
              type = "app";
              program = mkdocs;
              meta.description = "mkdocs with the Material theme";
            };
            packages = {
              inherit (self.lib.site { inherit pkgs; }) config site;
            };
          };
      }
    );
}
