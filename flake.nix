{
  description = "A non-pure Rootless podman tools for Nixos";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    test-vm = {
      url = "github:jimurrito/nixos-test-vm";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    burenix.url = "git+https://forgejo.immerhouse.com/jimurrito/burenix";
  };
  #
  outputs =
    {
      self,
      nixpkgs,
      test-vm,
      burenix,
      ...
    }:
    {
      #
      nixosModules.default.imports = [
        burenix.nixosModules.default
        ./src/options.nix
        ./src/config.nix
      ];
      #
      #
      #
      #
      # TestVM
      nixosConfigurations = {
        test-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            (import test-vm.baselineConfig { memorySize = 4096; })
            self.nixosModules.default
            # test config
            {
              services.podmanix = {
                enable = true;
                backups = {
                  enable = true;
                  encryption = {
                    enable = true;
                    keyPath = "/etc/hostname";
                  };
                  targetDirs = [
                    "/var/backups"
                    "/opt/backups"
                  ];
                };
                updates.enable = true;
                services.myapp = {
                  enable = true;
                  composeFile = ./test.yml;
                  backups = {
                    enable = true;
                    dataPaths = [ "/etc/fstab" ]; # testing
                  };
                };
              };
            }
            #
          ];
        };
      };
      #
      #
      #
    };
}
