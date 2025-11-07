{ config, pkgs, pkgsphp74, inputs, lib, libphp74, ... }:
let
  # Replace pkgs.php with the php version you want; ex pkgs.php83
  php = pkgsphp74.php74.buildEnv {
    extensions = { enabled, all }: enabled ++ (with all; [ 
      memcached 
      apcu 
      curl
      gd
      intl
      mbstring
      mysqli
      zip
      opcache
    ]); 
  };
in

{
services.mysql = {
  enable = true;
  package = pkgs.mysql80;
  settings.mysqld.bind-address = "0.0.0.0";
};
services.mysqlBackup = {
  enable = true;
  databases = [ "OwnCloud" ];
};

  services.cron = {
    enable = true;
    systemCronJobs = [
      "*/15 * * * *      ${config.services.httpd.user}    ${php}/bin/php /owncloud/owncloud/occ system:cron"
      "0 1 * * *       ${config.services.httpd.user}    ${php}/bin/php /owncloud/owncloud/occ dav:sync-system-addressbook"
      "0 1 * * *       ${config.services.httpd.user}    ${php}/bin/php /owncloud/owncloud/occ dav:cleanup-chunks"
    ];
  };

  # Disable logrotate for container deployment (logs go to journalctl which handles rotation)
  services.logrotate.enable = lib.mkForce false;

  services.httpd = {
    enable = true;
    user = "wwwrun";
    group = "wwwrun";
    adminAddr = "admin@localhost";
    
    phpPackage = php;
    enablePHP = true;
    
    phpOptions = ''
      upload_max_filesize = 2G
      post_max_size = 2G
      memory_limit = 512M
      mbstring.func_overload = 0
      default_charset = 'UTF-8'
      output_buffering = 0
    '';
    
    extraModules = [
      "rewrite"
      "headers"
      "env"
      "dir"
      "mime"
      "setenvif"
    ];
    
    virtualHosts = {
      "oc.oscam.in" = {
        documentRoot = "/owncloud/owncloud";
        
        extraConfig = ''
          # Security headers
          <IfModule mod_headers.c>
            Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains"
            Header always set X-Content-Type-Options "nosniff"
            Header always set X-Frame-Options "SAMEORIGIN"
            Header always set X-XSS-Protection "0"
            Header always set X-Robots-Tag "none"
            Header always set X-Download-Options "noopen"
            Header always set X-Permitted-Cross-Domain-Policies "none"
          </IfModule>
          
          # Allow .htaccess to override settings
          <Directory "/owncloud/owncloud">
            AllowOverride All
            Require all granted
            Options -Indexes +FollowSymLinks
            
            # DirectoryIndex is set in .htaccess but ensure it's available
            <IfModule mod_dir.c>
              DirectoryIndex index.php index.html
            </IfModule>
          </Directory>
          
          # Error documents
          ErrorDocument 403 /core/templates/403.php
          ErrorDocument 404 /core/templates/404.php
          
          # Enable rewrite engine (used by .htaccess)
          <IfModule mod_rewrite.c>
            RewriteEngine On
          </IfModule>
          
          # Set character encoding
          AddDefaultCharset utf-8
          
          # Disable mod_pagespeed if present
          <IfModule pagespeed_module>
            ModPagespeed Off
          </IfModule>
        '';
      };
    };
  };

  # Create owncloud directory owned by httpd user and a symlink 'data' pointing to /owncloud/owncloud/data
  # Using systemd-tmpfiles so it is realized at image/container boot.
  # systemd.tmpfiles.rules = [
  #   "d /usr/share 0755 root root - -"
  #   "d /usr/share/httpd 0755 ${config.services.httpd.user} ${config.services.httpd.group} - -"
  #   "d /usr/share/httpd/htdocs 0755 ${config.services.httpd.user} ${config.services.httpd.group} - -"
  #   "d /usr/share/httpd/htdocs/owncloud 0755 ${config.services.httpd.user} ${config.services.httpd.group} - -"
  #   "L+ /usr/share/httpd/htdocs/owncloud/data - - - - /owncloud/owncloud/data"
  # ];
}
