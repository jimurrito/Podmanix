{ lib, ... }:
with lib;
{
  #  Options for services overlay
  options.services = {
    #
    # Primary options
    podmanix = {
      default = { };
      #description = "Multiple Podman Compose services keyed by name.";
      enable = mkEnableOption "podmanix module";
      backups = {
        enable = mkEnableOption "Backups for podman services.";
        keyPath = mkOption {
          type = types.str;
          default = "/root/backup-key";
          description = "Key used to encrypt the compressed files.";
        };
        targetDirs = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Backup targets for the containers.";
        };
        rolloverIntervalDays = mkOption {
          type = types.number;
          default = 14;
          description = "Defines the age a backup needs to be, before it is pruned. Defaults to 14 (days).";
        };
        useSSH = mkOption {
          type = types.bool;
          default = false;
          description = "If toggled, scp will be used for the backup transfers.";
        };
        usePigz = mkOption {
          type = types.bool;
          default = false;
          description = "Toggles the use of Pigz (multi-threaded gzip) when compressing the archive. Pigz will use all cores and memory available.";
        };
      };
      updates = {
        enable = mkEnableOption "Updates for rootless podman services";
        updateTime = mkOption {
          type = types.str;
          default = "Thu, 4:00:00";
          description = "Time the update and restart will trigger. Defaults to 'Thur, 4:00:00'. Uses Systemd Timer formatting.";
        };
      };
      services = mkOption {
        default = { };
        description = "The podman compose services.";
        type = types.attrsOf (
          types.submodule (
            { name, ... }:
            {
              options = {
                enable = mkEnableOption "This podman compose service.";
                user = mkOption {
                  type = types.str;
                  default = name;
                  description = "System user to run the service under.";
                };
                group = mkOption {
                  type = types.str;
                  default = "podmanix";
                  description = "Group for the service user.";
                };
                composeFile = mkOption {
                  type = types.path;
                  description = "Path to the compose.yml file.";
                };
                firewall = {
                  allowedTCPPorts = mkOption {
                    type = types.listOf types.int;
                    default = [ ];
                    description = "Ports that should be opened on the local firewall.";
                  };
                  allowedUDPPorts = mkOption {
                    type = types.listOf types.int;
                    default = [ ];
                    description = "Ports that should be opened on the local firewall.";
                  };
                };
                backups = {
                  enable = mkEnableOption "Backups for podman services";
                  dataPaths = mkOption {
                    type = types.listOf types.str;
                    default = [ ];
                    description = "Path(s) to the Podman container's state data.";
                  };
                  tempDir = mkOption {
                    type = types.str;
                    default = "/tmp";
                    description = "Temporary directory used when compressing the backup.";
                  };
                  backupTime = mkOption {
                    type = types.str;
                    default = "Mon, 4:00:00";
                    description = "Time the backup will trigger. Defaults to 'Mon, 4:00:00'. Uses Systemd Timer formatting.";
                  };
                  useServiceUser = mkOption {
                    type = types.bool;
                    default = false;
                    description = "Uses the podman service user for the backup job. Default user is root.";
                  };
                };
              };
            }
          )
        );
      };
    };
  };
}
