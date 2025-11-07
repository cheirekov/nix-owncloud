# OwnCloud NixOS Docker Images

This project builds NixOS-based Docker/Podman images running OwnCloud with two different web server options:
1. **Nginx + PHP-FPM** (PHP 7.4 with APCu + Memcached extensions)
2. **Apache httpd + mod_php** (Same PHP 7.4 configuration)

Both images are generated reproducibly using `nixos-generators` via a Nix flake.

## Features

### Common Features (Both Images)
- PHP 7.4 (`php74.buildEnv`) with `memcached` and `apcu` extensions enabled
- OwnCloud cron tasks scheduled (system cron invoking `occ` commands)
- MySQL 8.0 with automated backups
- Large upload/post size support (2G)
- Memory limit: 512M
- Container sysctl: IPv4 forwarding enabled
- Firewall disabled; DNS nameservers preset; IPv6 disabled
- Uses Nix binary cache (internal) for multi-arch builds (x86_64 and aarch64)
- Minimal extra system packages: `bashInteractive`, `cacert`, `nix`
- Security headers: HSTS, X-Frame-Options, X-Content-Type-Options, X-Robots-Tag, etc.
- Data root: `/owncloud/owncloud` (ensure persistence via volume mount)

### Nginx Version (`oc-nginx-owncloud.nix`)
- Nginx configured for OwnCloud with strict security headers
- PHP-FPM pool with dynamic process management (max 50 children)
- FastCGI tuning and buffering
- Separate caching headers for static assets (CSS, JS, images, fonts)
- Custom location blocks for OwnCloud paths

### Apache Version (`oc-httpd-owncloud.nix`)
- Apache httpd with mod_php (not php-fpm)
- Uses ownCloud's stock `.htaccess` file for configuration
- `AllowOverride All` enabled for .htaccess support
- Required Apache modules: rewrite, headers, env, dir, mime, setenvif
- Logrotate disabled (logs go to journalctl for container compatibility)

## Architecture Overview

### Nginx Architecture
- Base: NixOS module composition via `nixos-generators.nixosGenerate` (format = docker)
- Web: Nginx virtual host `oc.oscam.in` (can be changed; SSL directives currently off)
- PHP: PHP-FPM pool `owncloud` with socket exposed to Nginx fastcgi
- Cron: OwnCloud maintenance commands every 15 minutes + nightly jobs (run as nginx user)

### Apache Architecture
- Base: Same NixOS module composition
- Web: Apache httpd virtual host `oc.oscam.in` with mod_php
- PHP: Integrated via mod_php (enablePHP = true)
- Configuration: Relies on ownCloud's `.htaccess` for URL rewriting and PHP settings
- Cron: OwnCloud maintenance commands every 15 minutes + nightly jobs (run as wwwrun user)

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

## Building the Images

### Nginx Version (x86_64):
```bash
nix build .#packages.x86_64-linux.dockerImage
```

### Apache/httpd Version (x86_64):
```bash
nix build .#packages.x86_64-linux.dockerImageHttpd
```

Result will be a symlink `result` pointing to a tarball (layered image export).

### For aarch64 (if adding analogous output):
```bash
# Nginx
nix build --system aarch64-linux .#packages.aarch64-linux.dockerImage

# Apache
nix build --system aarch64-linux .#packages.aarch64-linux.dockerImageHttpd
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

- **Domain**: Change `"oc.oscam.in"` in `services.nginx.virtualHosts` (nginx) or `services.httpd.virtualHosts` (Apache) to your FQDN.
- **Choose Web Server**: Build either `dockerImage` (Nginx) or `dockerImageHttpd` (Apache) depending on your preference.
- **Enable SSL / ACME**:
  - Uncomment `security.acme` section and set email.
  - Set `forceSSL = true` and provide certificates or rely on ACME.
- **PHP Version**:
  - Swap `php74` with another version from `phps` (e.g. `php83`) adjusting the buildEnv derivation in both modules.
- **Additional PHP Extensions**:
  - Extend the `extensions` list in `buildEnv` (same for both modules).
- **Add packages**:
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

### Nginx Version
- **PHP errors**: Inspect `/var/log/php-fpm/owncloud-error.log` inside container.
- **FastCGI socket issues**: Confirm `services.phpfpm.pools.owncloud.socket` path matches Nginx `fastcgi_pass`.
- **Large uploads failing**: Verify proxy / host limits; `client_max_body_size 0` in Nginx allows unlimited, but upstream reverse proxies may cap.

### Apache Version
- **PHP errors**: Check Apache error logs via `journalctl -u httpd` or within the container logs.
- **mod_php issues**: Verify `enablePHP = true` is set and `phpPackage` is properly configured.
- **.htaccess not working**: Ensure `AllowOverride All` is set in the Directory directive.
- **Logrotate conflict**: If you see logrotate errors, verify `services.logrotate.enable = lib.mkForce false;` is present in the module.

### Common Issues (Both Versions)
- **Cron not running**: Ensure systemd is functional (requires privileged mode).
- **MySQL connection issues**: Check if MySQL is running with `systemctl status mysql` inside container.
- **Large uploads failing**: Verify host-level proxy limits if behind a reverse proxy.

## Updating OwnCloud

Add/update derivation or fetch process (not included here). Place application code at `/owncloud/owncloud`. Persist external data volume to avoid data loss on rebuilds.

## License

This project (NixOS configuration files and documentation) is licensed under the **MIT License**. See the [LICENSE](LICENSE) file for details.

**Important Note**: This license applies only to the configuration files in this repository. OwnCloud itself is distributed under the AGPL v3 license and must be obtained separately. Users are responsible for complying with OwnCloud's licensing terms when deploying the software.

## References

- NixOS: https://nixos.org
- OwnCloud Admin Docs
- Nginx + PHP-FPM hardening guides
