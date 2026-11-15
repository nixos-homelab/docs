# Checks of the docs module on a system with shared's modules, set up as shared's manifests check sets one up: its
# manifests and image against the Kubernetes schemas, and the cluster site carrying the system's values
{
  self,
  inputs,
  pkgs,
  lib,
}:
let
  system = inputs.nixpkgs.lib.nixosSystem {
    modules = lib.attrValues inputs.homelab-shared.nixosModules ++ [
      self.nixosModules.docs
      {
        nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system;
        networking.hostName = "docs";
        # k8sss makes the SSH keys of wheel users step-ca admins. The private half of this one is gone
        users.users.admin = {
          isNormalUser = true;
          uid = 1000;
          extraGroups = [ "wheel" ];
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN+kj02ez01d/NBAbS3ybonaf76LMymdbEblV9pHEwZj admin@example.org"
          ];
        };
        homelab.workloads = {
          domain = "example.org";
          acmeProvider = "letsencrypt-staging";
          gatewayClassName = "example";
        };
        homelab.k3s = {
          enable = true;
          dataDir = "/var/lib/rancher/k3s";
        };
        homelab.cert-manager =
          let
            webhook-config = {
              provider = "inwx";
              secretName = "dns-credentials";
            };
          in
          {
            acme-staging-issuer = { inherit webhook-config; };
            acme-production-issuer = { inherit webhook-config; };
          };
        homelab.homepage.enable = true;
        homelab.docs = {
          enable = true;
          reservedIPs = [ "10.45.0.9" ];
        };
      }
    ];
  };
  inherit (system.config.homelab.docs) site;
in
{
  docs-manifests = inputs.homelab-shared.lib.checks.manifests {
    inherit pkgs;
    inherit (system) config;
    name = "docs-manifests";
  };
  # The values of the system on the cluster site: a set option, marked changed, the badge of an enabled section, and
  # no value for an option of a module the system doesn't import
  docs-cluster-site = pkgs.runCommand "docs-cluster-site" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python3 - ${site} <<'PY'
    import re, sys
    site = sys.argv[1]

    def row(page, name):
        html = open(f"{site}/{page}/index.html").read()
        match = re.search(r'<tr[^>]*id="%s"[^>]*>(.*?)</tr>' % re.escape(name), html, re.S)
        assert match, f"no row for {name} in {page}"
        return match.group(1)

    domain = row("shared/options/workloads", "homelab.workloads.domain")
    assert 'nd-value nd-changed' in domain and "example.org" in domain, domain
    k3s = open(f"{site}/shared/options/k3s/index.html").read()
    assert 'nd-badge nd-enabled' in k3s, "no enabled badge on k3s"
    # An option inside an option of a submodule type
    secret = row("shared/options/cert-manager", "homelab.cert-manager.acme-staging-issuer.webhook-config.secretName")
    assert 'nd-value nd-changed' in secret and "dns-credentials" in secret, secret
    # An option of a module the system doesn't import has no value
    sonarr = row("media/options/sonarr", "homelab.sonarr.enable")
    assert '<td class="nd-value">—</td>' in sonarr, sonarr
    print("cluster site checks passed")
    PY
    touch $out
  '';
}
