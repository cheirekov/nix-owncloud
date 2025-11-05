{ config, pkgs, pkgsphp74, inputs, lib, libphp74, ... }:
let
  # Replace pkgs.php with the php version you want; ex pkgs.php83
  php = pkgsphp74.php74.buildEnv {
    extensions = { enabled, all }: enabled ++ (with all; [ memcached apcu ]); 
  };
in

{
  services.cron = {
    enable = true;
    systemCronJobs = [
      "*/15 * * * *      ${config.services.nginx.user}    ${php}/bin/php /owncloud/owncloud/occ system:cron"
      "0 1 * * * *      ${config.services.nginx.user}    ${php}/bin/php /owncloud/owncloud/occ dav:sync-system-addressbook"
      "0 1 * * * *      ${config.services.nginx.user}    ${php}/bin/php /owncloud/owncloud/occ dav:cleanup-chunks"
    ];
  };
 services.phpfpm.phpPackage = php;
 #nixpkgs.hostPlatform = "aarch64-linux";
 services.phpfpm.pools.owncloud = {
   #phpOptions = ''
   #extension=${pkgs.phpExtensions.apcu}/lib/php/extensions/apcu.so
   #extension=${pkgs.phpExtensions.memcached}/lib/php/extensions/memcached.so'';
   user = config.services.nginx.user;
#   group = "users";
   settings = {
#     "listen.owner" = "nemo";
#     "listen.group" = "users";
     "listen.owner" = config.services.nginx.user;
     "pm" = "dynamic";
     "pm.max_children" = 50;
     "pm.start_servers" = 5;
     "pm.min_spare_servers" = 5;
     "pm.max_spare_servers" = 35;
     "pm.max_requests" = 500;
     "php_admin_value[access.log]" = "/var/log/php-fpm/owncloud-access.log";
     "php_admin_value[error_log]" = "/var/log/php-fpm/owncloud-error.log";
     "php_admin_flag[log_errors]" = "on";
     "php_admin_value[memory_limit]" = "512M";
     "php_admin_value[upload_max_filesize]" = "2G";
     "php_admin_value[post_max_size]" = "2G";
   };
   phpEnv."PATH" = lib.makeBinPath [ php ];
 };
# services.nginx.package = inputs.nginx-old.legacyPackages.x86_64-linux.nginx;


 services.nginx = {
#   user = "nemo";
#   group = "users";
   enable = true;
   virtualHosts = {
     "oc.mikro.work" = {
       forceSSL = false;
       enableACME = false;
       root = "/owncloud/owncloud";
       extraConfig = ''             
         add_header Strict-Transport-Security "max-age=15552000; includeSubDomains";
         add_header X-Content-Type-Options nosniff;
         add_header X-Frame-Options "SAMEORIGIN";
         add_header X-XSS-Protection "0";
         add_header X-Robots-Tag none;
         add_header X-Download-Options noopen;
         add_header X-Permitted-Cross-Domain-Policies none;
         
         client_max_body_size 0;
         fastcgi_buffers 64 4K;
         
         gzip off;
         
         error_page 403 /core/templates/403.php;
         error_page 404 /core/templates/404.php;
         
         index index.php;
        '';       
       locations = {
         # Exact match locations first
         "= /robots.txt" = {
           extraConfig = ''
             allow all;
             log_not_found off;
             access_log off;
           '';
         };
         
         "= /.well-known/carddav" = {
           extraConfig = ''
             return 301 $scheme://$host/remote.php/dav;
           '';
         };
         
         "= /.well-known/caldav" = {
           extraConfig = ''
             return 301 $scheme://$host/remote.php/dav;
           '';
         };
         
         # Main location block - exactly as in original config
         "/" = {
           extraConfig = ''
             rewrite ^ /index.php;
           '';
         };
         
         # Blocked paths - exactly as in original config
         "~ ^/(?:build|tests|config|lib|3rdparty|templates|data)/" = {
           extraConfig = '' 
             return 404;
           '';
         };
         
         "~ ^/(?:\\.|autotest|occ|issue|indie|db_|console)" = {
           extraConfig = '' 
             return 404;
           '';
         };
         
         # PHP handling - exactly as in original config
         "~ ^/(?:index|remote|public|cron|core/ajax/update|status|ocs/v[12]|updater/.+|ocs-provider/.+|core/templates/40[34])\\.php(?:$|/)" = {
           extraConfig = ''
             fastcgi_split_path_info ^(.+\\.php)(/.*)$;
             include ${pkgs.nginx}/conf/fastcgi_params;
             fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
             fastcgi_param PATH_INFO $fastcgi_path_info;
             fastcgi_param HTTPS on;
             fastcgi_param modHeadersAvailable true; #Avoid sending the security headers twice
             fastcgi_param front_controller_active true;
             fastcgi_pass unix:${config.services.phpfpm.pools.owncloud.socket};
             fastcgi_intercept_errors on;
             fastcgi_request_buffering off;
           '';
         };
         
         # Updater and ocs-provider - exactly as in original config
         "~ ^/(?:updater|ocs-provider)(?:$|/)" = {
           extraConfig = ''
             try_files $uri $uri/ =404;
             index index.php;
           '';
         };
         
         # CSS and JS files - exactly as in original config
         "~* \\.(?:css|js)$" = {
           extraConfig = ''
             try_files $uri /index.php$uri$is_args$args;
             add_header Cache-Control "public, max-age=7200";
             add_header X-Content-Type-Options nosniff;
             add_header X-Frame-Options "SAMEORIGIN";
             add_header X-XSS-Protection "0";
             add_header X-Robots-Tag none;
             add_header X-Download-Options noopen;
             add_header X-Permitted-Cross-Domain-Policies none;
             access_log off;
           '';
         };
         
         # Other static files - exactly as in original config
         "~* \\.(?:svg|gif|png|html|ttf|woff|ico|jpg|jpeg)$" = {
           extraConfig = ''
             try_files $uri /index.php$uri$is_args$args;
             access_log off;
           '';
         };
       };
     };
   };
 };

#  security.acme = {
#    acceptTerms = true;
#    defaults.email = "nemo+oc@mikro.work";
#  };
#  security.acme.certs = {
#    "oc.mikro.work".email = "nemo+oc@mikro.work";
#  };
}
