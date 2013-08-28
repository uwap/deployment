{ pkgs, config, nodes, resources, ... }:

with pkgs.lib;

let
  hydraRelease = import ./hydra/release.nix {};
  hydra = builtins.getAttr config.nixpkgs.system hydraRelease.build;

  buildUser = "hydrabuild";

  isBuildNode = name: node: hasAttr buildUser node.config.users.extraUsers;
  buildNodes = filterAttrs isBuildNode nodes;

  buildKey = resources.sshKeyPairs."hydra-build".private_key;
in {
  require = [ ./hydra/hydra-module.nix ];

  services.hydra = {
    inherit hydra;
    enable = true;
    hydraURL = "http://hydra.headcounter.org/";
    notificationSender = "hydra@headcounter.org";
    dbi = "dbi:Pg:dbname=hydra;";
  };

  nix.distributedBuilds = true;
  nix.buildMachines = flip mapAttrsToList buildNodes (hostName: node: {
    inherit hostName;
    inherit (node.config.nix) maxJobs;
    inherit (node.config.nixpkgs) system;
    sshKey = "/run/keys/buildkey.priv";
    sshUser = buildUser;
  });

  deployment.keys."buildkey.priv" = buildKey;
  deployment.storeKeysOnMachine = false;

  services.postgresql.enable = true;
  services.postgresql.package = pkgs.postgresql92;
  services.postgresql.authentication = ''
    local hydra hydra peer
  '';
}
