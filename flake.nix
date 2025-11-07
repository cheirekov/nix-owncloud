{
  description = "OwnCloud NixOS system packaged as a Docker image";

nixConfig = {
extra-substituters = "http://i2.mikro.work:12666/nau"; #use it if aarach64 build is needed
extra-trusted-public-keys = "nau:HISII/VSRjn+q5/T9Nrue5UmUU66qjppqCC1DEHuQic=";
};

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";
    phps.url = "github:fossar/nix-phps";
    nixphp74.url = "github:nixos/nixpkgs?rev=99fcf0ee74957231ff0471228e9a59f976a0266b";
  };

  outputs = { self, nixpkgs, nixos-generators, phps, ... }@inputs:
     let
    # Helper function to get packages for a specific system
    forSystem = system: {
      pkgs = nixpkgs.legacyPackages.${system};
      #pkgsphp74 = inputs.nixphp74.legacyPackages.${system};
      pkgsphp74 = inputs.phps.packages.${system};
      lib = nixpkgs.lib;
      libphp74 = inputs.nixphp74.lib;
    };
    
    # Pre-define common systems
    aarch64-linux = forSystem "aarch64-linux";
    x86_64-linux = forSystem "x86_64-linux";
   in
   {

    # Build the Docker image using nixos-generators (nginx version)
    packages.x86_64-linux.dockerImage = nixos-generators.nixosGenerate {
          specialArgs = {
          inherit inputs;
          libphp74 = x86_64-linux.libphp74;
          pkgsphp74 = x86_64-linux.pkgsphp74;
        
        };
      system = "x86_64-linux"; #Change to "aarch64-linux" for ARM systems
      modules = [ ./oc-nginx-owncloud.nix 
      {
        boot.isContainer = true;
        systemd.oomd.enable = false;
        networking.firewall.enable = false;
        networking.nameservers = [ "8.8.8.8" "1.1.1.1" ];
        networking.useDHCP = false;
        networking.useNetworkd = false;
        networking.enableIPv6 = false;
        boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
        #services.nscd.enable = false;
        system.stateVersion = "25.05";
        documentation.doc.enable = false;
        environment.systemPackages = with nixpkgs.legacyPackages.x86_64-linux; [
          bashInteractive
          cacert
          nix
       ];
      }
      ];
      format = "docker";
    };

    # Build the Docker image using nixos-generators (httpd/Apache version)
    packages.x86_64-linux.dockerImageHttpd = nixos-generators.nixosGenerate {
          specialArgs = {
          inherit inputs;
          libphp74 = x86_64-linux.libphp74;
          pkgsphp74 = x86_64-linux.pkgsphp74;
        
        };
      system = "x86_64-linux"; #Change to "aarch64-linux" for ARM systems
      modules = [ ./oc-httpd-owncloud.nix 
      {
        boot.isContainer = true;
        systemd.oomd.enable = false;
        networking.firewall.enable = false;
        networking.nameservers = [ "8.8.8.8" "1.1.1.1" ];
        networking.useDHCP = false;
        networking.useNetworkd = false;
        networking.enableIPv6 = false;
        boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
        #services.nscd.enable = false;
        system.stateVersion = "25.05";
        documentation.doc.enable = false;
        environment.systemPackages = with nixpkgs.legacyPackages.x86_64-linux; [
          bashInteractive
          cacert
          nix
       ] ++ [ x86_64-linux.pkgsphp74.php74 ];
      }
      ];
      format = "docker";
    };
  };
}
