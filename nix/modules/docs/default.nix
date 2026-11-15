# The docs site in the cluster: the same site as the public one, with the current value of every option it shows,
# compiled in from this system's configuration, served by static-web-server over TLS behind a LoadBalancer IP.
{ inputs, self, ... }:
{
  pkgs,
  lib,
  config,
  options,
  ...
}:
let
  cfg = config.homelab.docs;
  ccfg = config.homelab.cluster;
  inherit (pkgs.stdenv.hostPlatform) system;
  domain = "docs.${config.homelab.workloads.domain}";
  labels."app.kubernetes.io/name" = "docs";
  port = 8443;

  # The value of an option the site shows, as `{ value; changed; }`, or null when it has none: an option of a module
  # this system doesn't import, an unset option without a default, a value that throws. Options under `<name>`
  # (attrsOf) or `*` (listOf) get one value per instance. `tryEval` only catches throws, so missing attributes are
  # checked for on the way.
  missing = {
    _missing = true;
  };
  isMissing = v: lib.isAttrs v && v ? _missing;
  resolve =
    node: loc:
    if loc == [ ] then
      node
    else
      let
        head = builtins.head loc;
        tail = builtins.tail loc;
      in
      if head == "<name>" then
        if lib.isAttrs node then lib.filterAttrs (_: v: !isMissing v) (lib.mapAttrs (_: v: resolve v tail) node) else missing
      else if head == "*" then
        if lib.isList node then lib.filter (v: !isMissing v) (map (v: resolve v tail) node) else missing
      else if lib.isAttrs node && node ? ${head} then
        resolve node.${head} tail
      else
        missing;
  valueOf =
    _name: doc:
    let
      placeholder = lib.any (part: part == "<name>" || part == "*") doc.loc;
      opt = lib.attrByPath doc.loc null options;
      defined =
        if placeholder then
          !isMissing (resolve options (lib.take 1 doc.loc))
        else
          lib.isAttrs opt && opt ? isDefined && opt.isDefined;
      value = if placeholder then resolve config doc.loc else opt.value;
      # Forces what the page will print, so a value that throws drops out here rather than failing the site
      checked = builtins.tryEval (
        defined && !isMissing value && builtins.seq (lib.generators.toPretty { } value) true
      );
      ok = checked.success && checked.value;
    in
    if ok then
      {
        inherit value;
        # A definition above the option's own default (1500, mkOptionDefault), mkDefault included
        changed = !placeholder && opt.highestPrio < 1500;
      }
    else
      null;
  values = lib.filterAttrs (_: v: v != null) (
    lib.mapAttrs valueOf (removeAttrs (self.lib.options system) cfg.withoutValues)
  );

  site =
    (self.lib.site {
      inherit pkgs values;
      siteUrl = "https://${domain}/";
    }).site;

  image = pkgs.dockerTools.buildImage {
    name = "cluster.local/docs";
    copyToRoot = lib.optionals cfg.debug ccfg.debugTools;
    config.Entrypoint = [
      (lib.getExe pkgs.static-web-server)
      "--host=::"
      "--port=${toString port}"
      "--root=${site}"
      "--http2"
      "--http2-tls-cert=/tls/tls.crt"
      "--http2-tls-key=/tls/tls.key"
      "--health"
      "--compression"
    ];
  };
in
{
  options.homelab.docs = {
    enable = lib.mkEnableOption "the docs site, with the current values of this system's options";
    debug = lib.mkEnableOption "debug mode";
    reservedIPs = lib.mkOption {
      description = "Reserved IPs for the docs loadbalancer";
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    allowIngress = lib.mkOption {
      description = ''
        Groups allowed to reach the docs from outside the cluster (as `allowIngress` of a workload). Pods with `cluster`
        egress, client VPN groups among them, reach them either way.
      '';
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = lib.literalExpression ''[ "local-lan" ]'';
    };
    tlsDomains = lib.mkOption {
      description = "Domains of the docs serving certificate";
      type = lib.types.listOf lib.types.str;
      default = [ domain ];
      defaultText = lib.literalExpression ''[ "docs.''${config.homelab.workloads.domain}" ]'';
    };
    withoutValues = lib.mkOption {
      description = ''
        Options shown without their value. Their values hold the cluster manifests or what is derived from them, the
        docs workload among them, whose image holds the site: showing them would make the site depend on itself.
      '';
      type = lib.types.listOf lib.types.str;
      default = [
        "homelab.kubernetes"
        "homelab.cluster.manifests.<name>.content"
      ];
    };
    site = lib.mkOption {
      description = "The site as built for this system, current values included";
      type = lib.types.package;
      readOnly = true;
      default = site;
      defaultText = lib.literalExpression "the site with this system's values";
    };
  };
  imports = [
    inputs.homelab-shared.nixosModules.cluster
    inputs.homelab-shared.nixosModules.workloads
    inputs.homelab-shared.nixosModules.homepage
  ];
  config = lib.mkIf cfg.enable {
    homelab.cluster.images = [ image ];
    homelab.homepage = lib.mkIf config.homelab.homepage.enable {
      bookmarks.Homelab.Docs = {
        enable = lib.mkDefault true;
        description = "Options and their current values";
        href = "https://${domain}/";
        icon = "mdi-book-open-variant";
      };
    };
    homelab.kubernetes.submodules.instances.docs =
      let
        ipFamilies = {
          ipFamilies = (lib.optional ccfg.enableIPv4 "IPv4") ++ (lib.optional ccfg.enableIPv6 "IPv6");
        }
        // lib.optionalAttrs (ccfg.enableIPv4 && ccfg.enableIPv6) { ipFamilyPolicy = "RequireDualStack"; };
      in
      {
        submodule = "workload";
        args = {
          inherit (cfg) allowIngress;
          ports.https = port;
          container = {
            image = "${image.buildArgs.name}:${image.imageTag}";
            imagePullPolicy = "Never";
            livenessProbe.httpGet = {
              scheme = "HTTPS";
              port = "https";
              path = "/health";
            };
            readinessProbe.httpGet = {
              scheme = "HTTPS";
              port = "https";
              path = "/health";
            };
            volumeMounts."/tls" = {
              name = "tls";
              readOnly = true;
            };
          };
        };
        config.kubernetes.resources = {
          certificates.docs = {
            metadata = { inherit labels; };
            spec = {
              secretName = "docs-tls";
              commonName = domain;
              dnsNames = cfg.tlsDomains;
              issuerRef = {
                group = "cert-manager.io";
                kind = "ClusterIssuer";
                name = config.homelab.workloads.acmeProvider;
              };
            };
          };
          services.docs.spec = ipFamilies;
          services.docs-external = {
            metadata = {
              inherit labels;
              annotations = {
                "external-dns.alpha.kubernetes.io/hostname" = domain;
              }
              // lib.optionalAttrs (cfg.reservedIPs != [ ]) { "lbipam.cilium.io/ips" = lib.join "," cfg.reservedIPs; };
            };
            spec = ipFamilies // {
              type = "LoadBalancer";
              selector = labels;
              ports.https = {
                port = 443;
                targetPort = port;
              };
            };
          };
          deployments.docs.spec.template.spec.volumes.tls.secret.secretName = "docs-tls";
        };
      };
  };
}
