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
  rtBackup = podmanix-nixops.backups;
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
        #
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
    services.burenix = {
      enable = rtBackup.enable;
      keyPath = rtBackup.keyPath;
      backups = srvMapper (
        name: conf:
        let
          srvBackup = conf.backups;
          rtIdSwitch = id: (if srvBackup.useServiceUser then id else "root");
        in
        {
          #
          # Backup config for the compose service
          "podmanix-${name}" = mkIf srvBackup.enable {
            enable = conf.enable;
            user = rtIdSwitch conf.user;
            group = rtIdSwitch conf.group;
            sourceDirs = srvBackup.dataPaths;
            tempDir = srvBackup.tempDir;
            targetDirs = rtBackup.targetDirs;
            rolloverIntervalDays = rtBackup.rolloverIntervalDays;
            backupTime = srvBackup.backupTime;
            useSSH = rtBackup.useSSH;
            usePigz = rtBackup.usePigz;
            #
            # TODO: see if we can remove the script dependency
            preRunScript = {
              enable = true;
              source = ../scripts/pre.bash;
              arguments = "${name}";
            };
            postRunScript = {
              enable = true;
              source = ../scripts/post.bash;
              arguments = "${name}";
            };
          };
        }
      );
    };
    #
  };
}
