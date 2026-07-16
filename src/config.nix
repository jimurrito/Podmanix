{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  podmanix-nixops = config.services.podmanix;
  srvs = podmanix-nixops.services;
  #
  doUpdates = podmanix-nixops.updates.enable;
  updateTime = podmanix-nixops.updates.updateTime;
  #
  srvMapper =
    logic: (mkMerge (mapAttrsToList (sName: sConf: (mkIf sConf.enable (logic sName sConf))) srvs));
  #
in
{
  #
  # config to be implemented via the `options`
  config = mkIf podmanix-nixops.enable {
    #
    # Imports package for use in cli
    environment.systemPackages = [
      pkgs.podman-compose
    ];
    #
    # Enables podman
    virtualisation.podman.enable = true;
    #
    # Creates the rootless user and podmanix group that will run the podman containers
    users = {
      groups.podmanix = { };
      users = srvMapper (
        _: conf:
        mkIf (conf.user != "root") {
          ${conf.user} = {
            enable = conf.enable;
            group = conf.group;
            extraGroups = conf.extraGroups;
            isSystemUser = true;
            linger = true;
            createHome = true;
            home = "/var/podmanix/${conf.user}";
            subUidRanges = [
              {
                startUid = 100000;
                count = 65536;
              }
            ];
            subGidRanges = [
              {
                startGid = 100000;
                count = 65536;
              }
            ];
          };
        }
      );
    };
    #
    # security idmap wrappers
    # Allows non-root users to create a uid or gid
    security.wrappers = {
      newuidmap = {
        source = "${pkgs.shadow}/bin/newuidmap";
        setuid = true;
        owner = "root";
        group = "root";
      };
      newgidmap = {
        source = "${pkgs.shadow}/bin/newgidmap";
        setuid = true;
        owner = "root";
        group = "root";
      };
    };
    #
    # Networking firewall rules
    networking = srvMapper (
      _: conf: {
        firewall = conf.firewall;
      }
    );
    #
    # Creates the systemd service for the podman compose
    systemd = srvMapper (
      name: conf:
      let
        podman = getExe pkgs.podman;
        podmanCompose = getExe pkgs.podman-compose;
        userHome = config.users.users.${conf.user}.home;
        serviceDeps = [
          # allows acceses to the wrappers for new*idmap
          "/run/wrappers"
          pkgs.podman
          pkgs.podman-compose
        ];
      in
      {
        #
        # Podman compose service
        services.${name} = {
          enable = conf.enable;
          description = "Podman Compose Service (${name} as ${conf.user}:${conf.group})";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
          path = serviceDeps;
          serviceConfig = {
            User = conf.user;
            Group = conf.group;
            WorkingDirectory = userHome;
            ExecStart = ''
              ${podmanCompose} -f ${conf.composeFile} up --remove-orphans --pull
            '';
            ExecStop = ''
              ${podmanCompose} -f ${conf.composeFile} down -t 10
            '';
            Restart = "always";
            # has to use simple as the notify modalities seem to have issues with rootless
          };
        };
        #
        #
        # Update Service for compose service
        services."podmanix-update-${name}" = mkIf doUpdates {
          enable = true;
          description = "Podmanix Update Service for [${name}]";
          restartIfChanged = true;
          path = serviceDeps;
          serviceConfig = {
            Type = "oneshot";
            User = conf.user;
            Group = conf.group;
            WorkingDirectory = userHome;
            ExecStartPre = "${podmanCompose} -f ${conf.composeFile} pull";
            ExecStart = "${podmanCompose} -f ${conf.composeFile} restart";
            ExecStartPost = "${podman} system prune -f";
          };
        };
        # Update service timer
        timers."podmanix-update-${name}" = mkIf doUpdates {
          enable = true;
          description = "Triggers update and restart podmanix ${name} container services @ [${updateTime}]";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = updateTime;
          };
        };
        #
      }
    );
    #
    # Backups via Burenix
    # Due to permissions, most instances will run as root.
    services.burenix = mkIf (podmanix-nixops.backups.enable) {
      enable = true;
      backups = srvMapper (
        name: conf:
        let
          # config in services.podmanix.backups
          rtBackupConf = podmanix-nixops.backups;
          # config in services.podmanix.services.*.backups
          srvBackup = conf.backups;
          # root backups override
          srvBackupOverride = srvBackup.overrides;
          useOverride = srvBackupOverride.enable;
          #
          # should the backup config use the parent config or use override
          buConfig = if useOverride then srvBackupOverride else rtBackupConf;
          wUser = if useOverride then srvBackupOverride.user else conf.user;
          wGroup = if useOverride then srvBackupOverride.group else conf.group;
          #
          # script generator
          startScript = op: name: ''
            #!/usr/bin/env bash
            echo "Performing ${op} on Podman Containers in ${name}.service"
            systemctl ${op} "${name}.service"
            echo "${op} completed for ${name}.service"
          '';
          #
          #
          preStart = pkgs.runCommand "prestart.bash" { } ''
            echo -e '${startScript "stop" name}' > $out
            chmod 0555 $out
          '';
          postStart = pkgs.runCommand "poststart.bash" { } ''
            echo -e '${startScript "start" name}' > $out
            chmod 0555 $out
          '';
          #
        in
        {
          #
          # Backup config for the compose service
          # Enable if backups on the service are enabled
          "podmx-${name}" = mkIf srvBackup.enable {
            enable = srvBackup.enable;
            sourceDirs = srvBackup.dataPaths;
            tempDir = srvBackup.tempDir;
            # uses either service user/group or override
            user = wUser;
            group = wGroup;
            # uses override/root backup config
            targetDirs = buConfig.targetDirs;
            rollover = buConfig.rollover;
            backupTime = buConfig.backupTime;
            useSSH = buConfig.useSSH;
            usePigz = buConfig.usePigz;
            encryption = buConfig.encryption;
            checksum = buConfig.checksum;
            #
            preRunScript = {
              enable = true;
              file = preStart;
              arguments = "${name}";
            };
            postRunScript = {
              enable = true;
              file = postStart;
              arguments = "${name}";
            };
          };
        }
      );
    };
    #
    # Polkit settings to allow the burenix backup service stop/start the podman service
    security.polkit = mkIf (podmanix-nixops.backups.enable) {
      enable = true;
      extraConfig = srvMapper (
        name: conf:
        let
          # root backups override
          srvBackupOverride = conf.backups.overrides;
          useOverride = srvBackupOverride.enable;
          #
          wUser = if useOverride then srvBackupOverride.user else conf.user;
        in
        ''
          polkit.addRule(function(action, subject) {
             if (action.id == "org.freedesktop.systemd1.manage-units" &&
                 action.lookup("unit") == "${name}.service" &&
                 subject.user == "${wUser}") {
               return polkit.Result.YES;
             }
           });
        ''
      );
    };
    #
  };
}
