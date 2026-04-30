/*
  Initializes non-root user profiles for podman
  Required due to how the session is opened for the user accounts
*/
{
  lib,
  config,
  pkgs,
  ...
}:
let
  podxinit-nixops = config.services.podmanix-init;
in
with lib;
{
  #
  #
  options.services.podmanix-init = {
    # generic options
    default = { };
    enable = mkEnableOption "The podmanix-init module";
    user = mkOption {
      type = types.str;
      default = "root";
      description = "System user to run the backup service under. Defaults to root due to complex permissions needed";
    };
    group = mkOption {
      type = types.str;
      default = "podmanix";
      description = "Group for the service user.";
    };
    # Podman configs
    initCMD = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of podman service users that be initialized.";
    };
  };
  #
  #
  config = mkIf (podxinit-nixops.enable) {
    #
    environment.etc."podmanix/scripts/init.bash" = {
      text = concatStringsSep "\n" podxinit-nixops.initCMD;
      user = podxinit-nixops.user;
      group = podxinit-nixops.group;
      mode = "0444";
    };
    #
    # Systemd Service
    systemd = {
      services.podman-init = {
        enable = true;
        description = "Podmanix rootless user initialization service";
        restartIfChanged = true;
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        path = with pkgs; [
          util-linux
        ];
        serviceConfig = {
          Type = "oneshot";
          User = podxinit-nixops.user;
          Group = podxinit-nixops.group;
          ExecStart = ''
            ${getExe pkgs.bash} ${config.environment.etc."podmanix/scripts/init.bash".source}
          '';
        };
      };
      #
    };
    #
  };
  #
  #
}
