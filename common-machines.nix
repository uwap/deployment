{ pkgs, lib, config, ... }:

let
  vuizvuiRev = "408b7de48eb41828d70d247fb152c8e5bd45fb5e";
  vuizvuiUrl = "https://github.com/openlab-aux/vuizvui/archive/"
             + "${vuizvuiRev}.tar.gz";
  vuizvui = fetchTarball vuizvuiUrl;
  vim = import "${vuizvui}/modules/user/aszlig/programs/vim/default.nix";

in {
  imports = [ ./common.nix vim ];

  vuizvui.user.aszlig.programs.vim.enable = true;

  deployment.targetEnv = lib.mkOverride 900 "hetzner";

  environment.systemPackages = with pkgs; [
    atop htop iotop
    sysstat dstat
    smartmontools
    perf-tools
    netrw
  ];

  services.openntpd.enable = true;

  nix = {
    package = pkgs.nixUnstable;
    nrBuildUsers = 100;
    useChroot = true;
    readOnlyStore = true;
    buildCores = 0;
  };

  nixpkgs.config.allowUnfree = true;
  hardware.cpu.intel.updateMicrocode = true;

  time.timeZone = "Europe/Berlin";
}
