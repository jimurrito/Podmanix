/*
  Update service for the Podmanix service configurations
  Will stop/start containers that have available updates
  Prunes dangleing resources once updated
*/
{
  lib,
  config,
  pkgs,
  ...
}:
let
  podxupdate-nixops = config.services.podmanix-update;
in
with lib;
{
  #
  #
  options.services.podmanix-update = {
    # generic options
    default = { };
    description = "Update module for Podmanix. Should not be used directly.";
    enable = mkEnableOption "podmanix-update module";
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
    updateCMD = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Update CMD for each Podmanix configuration. Set from 'services.podmanix'.";
    };
    # trigger time
    updateTime = mkOption {
      type = types.str;
      default = "Thur, 4:00:00";
      description = "Time the update and restart will trigger. Defaults to 'Thur, 4:00:00'. Uses Systemd Timer formatting.";
    };
  };
  #
  #
  config = mkIf (podxupdate-nixops.enable) {
    #
    # File containing all the update commands.
    # Typically a list of `runuser` commands that will handle the updates
    environment.etc."podmanix/scripts/update.bash" = {
      text = concatStringsSep "\n" podxupdate-nixops.updateCMD;
      user = podxupdate-nixops.user;
      group = podxupdate-nixops.group;
      mode = "0444";
    };
    #
    #
    # Systemd Service
    systemd = {
      services.podmanix-update = {
        enable = true;
        description = "Podmanix Update Service";
        restartIfChanged = true;
        path = with pkgs; [
          util-linux
        ];
        serviceConfig = {
          Type = "oneshot";
          User = podxupdate-nixops.user;
          Group = podxupdate-nixops.group;
          ExecStart = ''
            ${getExe pkgs.bash} ${config.environment.etc."podmanix/scripts/update.bash".source}
          '';
        };
      };
      #
      timers.podmanix-update = {
        enable = true;
        description = "Triggers update and restart podmanix container services @ [${podxupdate-nixops.updateTime}]";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = podxupdate-nixops.updateTime;
        };
      };
    };
    #
  };
}
