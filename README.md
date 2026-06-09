# Podmanix

![Nix](https://img.shields.io/badge/language-Nix-5277C3?logo=nixos)
![License](https://img.shields.io/badge/license-GPL%20v3-blue)

A NixOS module for declaratively managing rootless Podman containers via `podman-compose`. Podmanix handles the full lifecycle of containerized services — initialization, automatic updates, firewall rules, and encrypted backups — all driven by a single `services.podmanix` configuration block.

The best part is... you can bring your existing `yaml` files.

## Table of Contents

- [Requirements](#requirements)
- [Usage](#usage)
  - [Pseudo-code Example](#pseudo-code-example)
  - [Real Example](#real-example)
  - [Flake Setup](#flake-setup)
- [Options Reference](#options-reference)
  - [Top-level](#top-level)
  - [services.\<name\>](#servicesnname)
  - [updates](#updates)
  - [backups](#backups)
- [How It Works](#how-it-works)
- [User & Directory Layout](#user--directory-layout)
- [License](#license)

## Requirements

- NixOS with flakes enabled

## Usage

### Pseudo-code Example

```nix
{ inputs, ... }:
{
  imports = [ inputs.podmanix.nixosModules.default ];

  services.podmanix = {
    enable = true;

    services.<service-name> = {
      enable      = true;
      composeFile = <path-to-compose-yml>;

      firewall.allowedTCPPorts = [ <port> ];

      backups = {
        enable    = true;
        dataPaths = [ "<path-to-data>" ];
      };
    };

    updates.enable = true;

    backups = {
      enable     = true;
      keyPath    = "<path-to-encryption-key>";
      targetDirs = [ "<path-to-backup-destination>" ];
    };
  };
}
```

### Real Example

```nix
{ inputs, ... }:
{
  imports = [ inputs.podmanix.nixosModules.default ];

  services.podmanix = {
    enable = true;

    services.myapp = {
      enable      = true;
      composeFile = ./compose/myapp.yml;

      firewall.allowedTCPPorts = [ 8080 ];

      backups = {
        enable    = true;
        dataPaths = [ "/var/podmanix/myapp/data" ];
      };
    };

    updates.enable = true;

    backups = {
      enable     = true;
      keyPath    = "/root/backup-key";
      targetDirs = [ "/mnt/backups" ];
    };
  };
}
```

Apply with `nixos-rebuild switch`.

### Flake Setup

Add Podmanix to your flake inputs and wire up nixpkgs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    podmanix = {
      url = "git+https://forgejo.immerhouse.com/jimurrito/podmanix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, podmanix, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        podmanix.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

## Options Reference

All options live under `services.podmanix`.

### Top-level

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | bool | `false` | Enable the Podmanix module |

---

### `services.<name>`

One entry per containerized service, keyed by name.

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | bool | `false` | Enable this service |
| `user` | string | `<name>` | System user the service runs as |
| `group` | string | `"podmanix"` | System group for the service user |
| `composeFile` | path | — | Path to the `compose.yml` file |
| `firewall.allowedTCPPorts` | list of int | `[]` | TCP ports to open in the firewall |
| `firewall.allowedUDPPorts` | list of int | `[]` | UDP ports to open in the firewall |
| `backups.enable` | bool | `false` | Enable backups for this service |
| `backups.dataPaths` | list of string | `[]` | Paths to include in the backup archive |
| `backups.tempDir` | string | `"/tmp"` | Temporary directory used during compression |
| `backups.backupTime` | string | `"Mon, 4:00:00"` | Backup schedule (systemd calendar expression) |
| `backups.useServiceUser` | bool | `false` | Run the backup job as the service user instead of root |

---

### `updates`

Controls automatic image updates across all services.

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | bool | `false` | Enable automatic updates |
| `updateTime` | string | `"Thu, 4:00:00"` | Update schedule (systemd calendar expression) |

---

### `backups`

Global backup settings shared across all per-service backup jobs.

> **Note:** Backup encryption is mandatory and cannot be disabled. A valid encryption key at `keyPath` is always required when backups are enabled.

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | bool | `false` | Enable the backup system |
| `keyPath` | string | `"/root/backup-key"` | Path to the encryption key |
| `targetDirs` | list of string | `[]` | Destination directories for backup archives |
| `rolloverIntervalDays` | number | `14` | Days before old backups are pruned |
| `useSSH` | bool | `false` | Transfer backups via SCP |
| `usePigz` | bool | `false` | Use `pigz` (multi-threaded gzip) for compression |

## How It Works

1. **Rebuild** — NixOS creates system users, copies compose files to `/etc/podmanix/compose/`, and generates systemd units for each service.
2. **Init** — Before each service starts, `podman info` is run as the service user to bootstrap the rootless Podman environment.
3. **Run** — Each service runs `podman-compose up` and restarts automatically on failure.
4. **Update** — A systemd timer pulls new images and restarts the service on the configured schedule, then prunes unused resources.
5. **Backup** — A [Burenix](https://github.com/jimurrito/burenix)-managed timer stops the service, compresses and encrypts the configured data paths, transfers them to the target destination(s), then restarts the service.

## User & Directory Layout

Each service gets a dedicated system user with:

- Home directory at `/var/podmanix/<user>/`
- Subuid/subgid range `100000–165535` (required for rootless Podman)
- Lingering enabled so the user's systemd session persists after logout

Services configured with `user = "root"` skip user creation and rootless init entirely — the service runs with full root privileges. This is not recommended unless required.

## License

[GPL v3](LICENSE.md)
