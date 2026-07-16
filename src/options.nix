{ lib, ... }:
with lib;
let
  # creates sub module options for a dynamic option
  mkDynSubmod = mod: types.attrsOf (types.submodule mod);
  # creates sub module options for a static option
  mkSubmod =
    mod:
    types.submodule {
      options = mod;
    };
in
{
  #  Options for services overlay
  options.services.podmanix = {
    description = "Multiple Podman Compose services keyed by name.";
    enable = mkEnableOption "podmanix module";
    backups = mkOption {
      description = "Root configuration options for Podmanix backups via Burenix. Applies to all podmanix VMs unless they opt-out.";
      type = mkSubmod {
        enable = mkEnableOption "Backups for podman services.";
        # user and group are not set here as
        # the services will run under the rootless user
        # unless specified under *.backups.overrides.{user,group}
        targetDirs = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Backup targets for the containers.";
        };
        tempDir = mkOption {
          type = types.str;
          default = "/tmp";
          description = "Temporary directory used when compressing/encrypting the backup.";
        };
        rollover = mkOption {
          description = "Optional rollover of old archives within the target directories.";
          type = mkSubmod {
            enable = mkEnableOption "Rollover of existing backupfiles";
            intervalDays = mkOption {
              type = types.number;
              default = 14;
              description = "Defines the age, in days, a backup needs to be before it is pruned. Defaults to (14) days.";
            };
          };
        };
        backupTime = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Time the backup will trigger. Defaults to null meaning disabled. Uses Systemd Timer formatting.";
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
        encryption = mkOption {
          description = "Uses `gpg` for encryption and integrity checks.";
          type = mkSubmod {
            enable = mkEnableOption "enables use of gpg";
            keyPath = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Sets the encryption keypath for all containers that enable backups.";
            };
          };
        };
        checksum = mkEnableOption "Enables use of checksum validation. Uses for sha256 for non-encrypted backups. GPG for encrypted ones.";
      };
    };
    updates = mkOption {
      type = mkSubmod {
        enable = mkEnableOption "Updates for rootless podman services";
        updateTime = mkOption {
          type = types.str;
          default = "Thu, 4:00:00";
          description = "Time the update and restart will trigger. Defaults to 'Thur, 4:00:00'. Uses Systemd Timer formatting.";
        };
      };
    };
    services = mkOption {
      description = "The podman compose services.";
      type = mkDynSubmod (
        { name, ... }: {
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
            extraGroups = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Additional groups for the rootless user";
            };
            composeFile = mkOption {
              type = types.path;
              description = "Path to the compose.yml file.";
            };
            firewall = mkOption {
              description = "Firewall ports to open on the host.";
              type = mkSubmod {
                allowedTCPPorts = mkOption {
                  type = types.listOf types.int;
                  default = [ ];
                  description = "TCP Ports that should be opened on the local firewall.";
                };
                allowedUDPPorts = mkOption {
                  type = types.listOf types.int;
                  default = [ ];
                  description = "UDP Ports that should be opened on the local firewall.";
                };
              };
            };
            backups = mkOption {
              description = "The backup config specific to this podman service.";
              type = mkSubmod {
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
                overrides = mkOption {
                  description = "Overrides configurations imposed by the root `podmanix.backups` config. Please note that once enables, no unset backup configurations will be inherited.";
                  type = mkSubmod {
                    enable = mkEnableOption "Enable the use of overrides.";
                    user = mkOption {
                      type = types.str;
                      default = name;
                      description = "System user to run the backup service under. Defaults to root due to complex permissions needed.";
                    };
                    group = mkOption {
                      type = types.str;
                      default = "podmanix";
                      description = "Group for the service.";
                    };
                    targetDirs = mkOption {
                      type = types.listOf types.str;
                      default = [ ];
                      description = "Backup targets for the containers.";
                    };
                    tempDir = mkOption {
                      type = types.str;
                      default = "/tmp";
                      description = "Temporary directory used when compressing/encrypting the backup.";
                    };
                    rollover = mkOption {
                      description = "Optional rollover of old archives within the target directories.";
                      type = mkSubmod {
                        enable = mkEnableOption "Rollover of existing backupfiles";
                        intervalDays = mkOption {
                          type = types.number;
                          default = 14;
                          description = "Defines the age, in days, a backup needs to be before it is pruned. Defaults to (14) days.";
                        };
                      };
                    };
                    backupTime = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Time the backup will trigger. Defaults to null meaning disabled. Uses Systemd Timer formatting.";
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
                    encryption = mkOption {
                      description = "Uses `gpg` for encryption and integrity checks.";
                      type = mkSubmod {
                        enable = mkEnableOption "enables use of gpg";
                        keyPath = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                          description = "Sets the encryption keypath for all containers that enable backups.";
                        };
                      };
                    };
                    checksum = mkEnableOption "Enables use of checksum validation. Uses for sha256 for non-encrypted backups. GPG for encrypted ones.";
                  };
                };
              };
            };
          };
        }
      );
    };
  };
}
