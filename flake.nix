{
  description = "homelab-docs";
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
    homelab-media = {
      url = "github:nixos-homelab/media";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.docs.follows = "docs";
      inputs.homelab-shared.follows = "homelab-shared";
      inputs.homelab-networking.follows = "homelab-networking";
    };
    homelab-monitoring = {
      url = "github:nixos-homelab/monitoring";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.docs.follows = "docs";
      inputs.homelab-shared.follows = "homelab-shared";
    };
    homelab-finance = {
      url = "github:nixos-homelab/finance";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.docs.follows = "docs";
      inputs.homelab-shared.follows = "homelab-shared";
    };
    homelab-networking = {
      url = "github:nixos-homelab/networking";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.docs.follows = "docs";
      inputs.homelab-shared.follows = "homelab-shared";
    };
    homelab-personal = {
      url = "github:nixos-homelab/personal";
      inputs.systems.follows = "systems";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.docs.follows = "docs";
      inputs.homelab-shared.follows = "homelab-shared";
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
        flake = {
        };
        perSystem =
          {
            system,
            pkgs,
            lib,
            ...
          }:
          {
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
                      ${lib.getExe pkgs.mkdocs} "$@"
                    '';
                  }
                ];
              };
            };
            apps.mkdocs = {
              type = "app";
              program = lib.getExe pkgs.mkdocs;
            };
            packages = {
              config = pkgs.callPackage ./nix/packages/config {
                docsLib = inputs.docs.lib;
                modules = {
                  inherit (inputs)
                    homelab-shared
                    homelab-media
                    homelab-monitoring
                    homelab-finance
                    homelab-networking
                    homelab-personal
                    ;
                };
                additionalSettings = {
                  site_author = "Anders Ingemann";
                  remote_branch = "main";
                };
              };
            };
          };
      }
    );
}
