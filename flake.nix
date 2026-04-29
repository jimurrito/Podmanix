{
  description = "A non-pure Rootless podman tools for Nixos";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    burenix.url = "git+https://forgejo.immerhouse.com/jimurrito/burenix";
  };
  #
  outputs =
    { ... }:
    {
      #
      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          podmanix-nixops = config.services.podmanix;
        in
        with lib;
        {
          #
          # Imports supplimentary flakes
          imports = [
            ./modules/init.nix
            ./modules/update.nix
          ];
          #
          #  Options for services overlay
          options.services.podmanix = {
            default = { };
            description = "Multiple Podman Compose services keyed by name.";
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
          #
          # config to be implemented via the `options`
          config = mkIf (podmanix-nixops.enable) {
            #
            # Imports package and runs the install steps
            environment.systemPackages = [
              pkgs.podman-compose
            ];
            #
            # Enables podman
            virtualisation.podman.enable = true;
            #
            # Imports compose files to etc
            environment = {
              etc = mkMerge (
                mapAttrsToList (name: conf: {
                  # Podman compose files for each logical grouping of podman containers
                  "podmanix/compose/${name}.yml" = {
                    enable = conf.enable;
                    source = conf.composeFile;
                    user = conf.user;
                    group = conf.group;
                    mode = "0444";
                  };
                }) podmanix-nixops.services
              );
            };
            #
            # Creates the rootless user and podmanix group that will run the podman containers
            users = {
              groups.podmanix = { };
              users =
                let
                  guid = [
                    {
                      startUid = 100000;
                      count = 65536;
                    }
                  ];
                in
                mkMerge (
                  mapAttrsToList (
                    name: conf:
                    mkIf (conf.enable && conf.user != "root") {
                      ${conf.user} = {
                        enable = conf.enable;
                        isNormalUser = true;
                        group = conf.group;
                        linger = true;
                        createHome = true;
                        home = "/var/podmanix/${conf.user}";
                        subUidRanges = guid;
                        subGidRanges = guid;
                      };
                    }
                  ) podmanix-nixops.services
                );
            };
            #
            # Networking firewall rules
            networking = mkMerge (
              mapAttrsToList (
                name: conf:
                mkIf (conf.enable) {
                  firewall = conf.firewall;
                }
              ) podmanix-nixops.services
            );
            #
            # Creates the systemd service for the podman compose
            systemd =
              let
                etcComposePath = "/etc/podmanix/compose";
              in
              mkMerge (
                mapAttrsToList (
                  name: conf:
                  mkIf (conf.enable) {
                    services.${name} = {
                      enable = conf.enable;
                      description = "Podman Compose Service (${name} as ${conf.user}:${conf.group})";
                      # have to be after the initializer to ensure the user profile is properly setup
                      after = [ "podman-init.service" ];
                      wantedBy = [ "multi-user.target" ];
                      path = with pkgs; [
                        podman
                        podman-compose
                        shadow
                      ];
                      serviceConfig = {
                        User = conf.user;
                        Group = conf.group;
                        #
                        ExecStart = ''
                          ${getExe pkgs.podman-compose} \
                            -f ${etcComposePath}/${name}.yml up \
                            --remove-orphans --pull
                        '';
                        # IMPORTANT: avoid referencing config here to prevent recursion
                        ExecStop = ''
                          ${getExe pkgs.podman-compose} -f ${etcComposePath}/${name}.yml down -t 10
                        '';
                        Restart = "always";
                        # has to use simple as the notify modalities seem to have issues with rootless
                        Type = "simple";
                      };
                    };
                  }
                ) podmanix-nixops.services
              );
            #
            # Initialization config
            services.podmanix-init = mkMerge (
              mapAttrsToList (
                name: conf:
                mkIf (conf.enable && conf.user != "root") {
                  enable = conf.enable;
                  # No need to init the 'home' podman config for root
                  initCMD = [
                    "runuser -l ${conf.user} -c 'podman info >> /dev/null && echo ${name} as ${conf.user} initialized'"
                  ];
                }
              ) podmanix-nixops.services
            );
            #
            # Update configuration
            services.podmanix-update =
              let
                update-nixops = podmanix-nixops.updates;
              in
              mkMerge (
                mapAttrsToList (
                  name: conf:
                  mkIf (update-nixops.enable && conf.enable) {
                    enable = conf.enable;
                    updateTime = update-nixops.updateTime;
                    updateCMD = [
                      ''
                        runuser -l ${conf.user} -c 'podman-compose -f /etc/podman-compose/${name}.yml pull && echo ${name} as ${conf.user} updated'
                        systemctl restart ${name}.service && echo ${name} as ${conf.user} restarted post-update
                        runuser -l ${conf.user} -c 'podman system prune -f'
                      ''
                    ];
                  }
                ) podmanix-nixops.services
              );
            #
            # Backup configuration via Burenix
            services.burenix =
              let
                backup-nixops = podmanix-nixops.backups;
              in
              {
                enable = backup-nixops.enable;
                keyPath = backup-nixops.keyPath;
                backups = mkMerge (
                  mapAttrsToList (
                    name: conf:
                    mkIf (conf.backups.enable) {
                      "podmanix-${name}" = {
                        enable = conf.backups.enable;
                        user = if (conf.backups.useServiceUser) then conf.user else "root";
                        group = if (conf.backups.useServiceUser) then conf.group else "root";
                        sourceDirs = conf.backups.dataPaths;
                        tempDir = conf.backups.tempDir;
                        targetDirs = backup-nixops.targetDirs;
                        rolloverIntervalDays = backup-nixops.rolloverIntervalDays;
                        backupTime = conf.backups.backupTime;
                        useSSH = backup-nixops.useSSH;
                        usePigz = backup-nixops.usePigz;
                        preRunScript = {
                          enable = true;
                          source = ./scripts/pre.bash;
                          arguments = "${name}";
                        };
                        postRunScript = {
                          enable = true;
                          source = ./scripts/post.bash;
                          arguments = "${name}";
                        };
                      };
                    }
                  ) podmanix-nixops.services
                );
              };
            #
            #
          };
        };
    };
}
