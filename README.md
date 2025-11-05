# OwnCloud NixOS Docker Image (Nginx + PHP-FPM 7.4)

This project builds a NixOS-based Docker/Podman image running OwnCloud behind Nginx and PHP-FPM (PHP 7.4 with APCu + Memcached extensions). The image is generated reproducibly using `nixos-generators` via a Nix flake.

## Features

- Nginx configured for OwnCloud (strict security headers, fastcgi tuning, large upload sizes).
- PHP-FPM 7.4 (`php74.buildEnv`) with `memcached` and `apcu` extensions enabled.
- OwnCloud cron tasks scheduled (system cron invoking `occ` commands).
- Tuned PHP-FPM pool (dynamic, memory limits, large upload/post size 2G).
- Optional ACME / SSL sections present but commented (not tested).
- Container sysctl: IPv4 forwarding enabled.
- Firewall disabled; DNS nameservers preset; IPv6 disabled.
- Uses Nix binary cache (internal) for multi-arch builds (x86_64 and aarch64).
- Minimal extra system packages: `bashInteractive`, `cacert`, `nix`.

## Architecture Overview

Component summary:
- Base: NixOS module composition via `nixos-generators.nixosGenerate` (format = docker).
- Web: Nginx virtual host `oc.mikro.work` (can be changed; SSL directives currently off).
- PHP: PHP-FPM pool `owncloud` with socket exposed to Nginx fastcgi.
- Cron: OwnCloud maintenance commands every 15 minutes + nightly jobs.
- Extensions: `memcached`, `apcu` statically added via `php74.buildEnv`.
- Security: Several headers set (HSTS, X-Frame-Options, X-Content-Type-Options, etc).
- Data root: `/owncloud/owncloud` (ensure persistence via volume mount).

## Flake Structure

Key parts from `flake.nix`:
- Inputs:
  - `nixpkgs` pinned to `nixos-25.05`.
  - `nixos-generators` for image building.
  - `phps` for PHP package set.
  - Dedicated `nixphp74` revision (lib usage).
- Helper `forSystem` abstraction to obtain `pkgs`, `pkgsphp74`, `lib`.
- Defined image: `packages.x86_64-linux.dockerImage`.
  - To target aarch64 adjust `system = "aarch64-linux"` and add corresponding `packages.aarch64-linux.dockerImage` entry or duplicate stanza.
- Extra Nix config (binary cache):
  - `extra-substituters = http://i2.mikro.work:12666/nau`
  - `extra-trusted-public-keys = nau:HISII/VSRjn+q5/T9Nrue5UmUU66qjppqCC1DEHuQic=`

## PHP / Nginx Configuration Notes (`oc-nginx-owncloud.nix`)

- `php = pkgsphp74.php74.buildEnv { extensions = { enabled, all }: enabled ++ (with all; [ memcached apcu ]); };`
- PHP-FPM pool tuning:
  - Max children 50; memory limit 512M.
  - Upload/Post size 2G (adjust if needed).
- Nginx locations mimic standard OwnCloud recommended config including:
  - Blocking sensitive paths.
  - FastCGI param configuration (`SCRIPT_FILENAME`, `PATH_INFO`, `HTTPS on`).
  - Separate caching headers for static assets (`css`, `js`, images, fonts).
  - Rewrite root to `index.php`.

## Building the Image

Default (x86_64):
```bash
nix build .#packages.x86_64-linux.dockerImage
```

Result will be a symlink `result` pointing to a tarball (layered image export).

For aarch64 (if adding analogous output):
```bash
nix build --system aarch64-linux .#packages.aarch64-linux.dockerImage
```
(Requires host or remote builder capable of aarch64; leverage provided substituter.)

## Importing Into Docker / Podman

Use `docker import` (not `docker load`) because the output is a raw filesystem tar:

```bash
docker import result my-owncloud:nixos
# Or specify path if result is a directory pointing to the tar:
docker import $(readlink -f result) my-owncloud:nixos
```

Podman equivalent:
```bash
podman import result my-owncloud:nixos
```

(If `result` is a directory containing a `tar` file, import that file directly.)

## Running (Privileged Requirement)

Container must run privileged (due to systemd + certain kernel expectations inside NixOS base):

```bash
docker run --privileged -d \
  --name owncloud \
  -p 80:80 \
  -v owncloud-data:/owncloud/owncloud/data \
  my-owncloud:nixos
```

Podman:
```bash
podman run --privileged -d \
  --name owncloud \
  -p 80:80 \
  -v owncloud-data:/owncloud/owncloud/data \
  my-owncloud:nixos
```

Adjust host port / volumes as required. Persist `/owncloud/owncloud/data` (and optionally config/apps directories if you separate them).

## Customization

- Domain: Change `"oc.mikro.work"` in `services.nginx.virtualHosts` to your FQDN.
- Enable SSL / ACME:
  - Uncomment `security.acme` section and set email.
  - Set `forceSSL = true` and provide certificates or rely on ACME.
- PHP Version:
  - Swap `php74` with another version from `phps` (e.g. `php83`) adjusting the buildEnv derivation.
- Additional PHP Extensions:
  - Extend the `extensions` list in `buildEnv`.
- Add packages:
  - Insert into `environment.systemPackages` in the flake module list.

## Multi-Arch Notes

Binary cache lines in `flake.nix` allow faster aarch64 builds when a cache is available. Without cache expect longer compilation. Ensure the substituter is reachable from your build environment.

## Limitations / Caveats

- SSL/ACME untested (configuration present but commented).
- No firewall inside container; rely on host-level controls.
- Container expects privileged mode (systemd + cron). Not tuned for rootless operation.
- IPv6 disabled explicitly.
- Image size may be larger than minimal due to full Nix store closure.

## Troubleshooting

- PHP errors: Inspect `/var/log/php-fpm/owncloud-error.log` inside container.
- FastCGI socket issues: Confirm `services.phpfpm.pools.owncloud.socket` path matches Nginx `fastcgi_pass`.
- Large uploads failing: Verify proxy / host limits; `client_max_body_size 0` in Nginx allows unlimited, but upstream reverse proxies may cap.
- Cron not running: Ensure systemd is functional (requires privileged).

## Updating OwnCloud

Add/update derivation or fetch process (not included here). Place application code at `/owncloud/owncloud`. Persist external data volume to avoid data loss on rebuilds.

## License

Provide appropriate licensing for OwnCloud and any added files (not specified here).

## References

- NixOS: https://nixos.org
- OwnCloud Admin Docs
- Nginx + PHP-FPM hardening guides
