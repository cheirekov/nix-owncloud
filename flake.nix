{
  description = "OwnCloud NixOS system packaged as a Docker image";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixphp74.url = "github:nixos/nixpkgs?rev=99fcf0ee74957231ff0471228e9a59f976a0266b";
    flake-utils.url = "github:numtide/flake-utils";
    phps.url = "github:fossar/nix-phps";
  };

  outputs = { self, nixpkgs, nixos-generators, flake-utils, phps, nixphp74, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
    in
    flake-utils.lib.eachSystem systems (system:
      let
        pkgs = import nixpkgs { inherit system; };
        pkgsphp74 = phps.packages.${system};
        lib = nixpkgs.lib;
        libphp74 = nixphp74.lib;

        # Common container adjustments
        baseContainerModule = {
          boot.isContainer = true;
          networking.firewall.enable = false;
          services.openssh.enable = false;
          users.users.root.initialPassword = "nixos";
          environment.systemPackages = with pkgs; [
            curl
            vim
            htop
          ];
        };

        owncloudModules = [
          ./oc-nginx-owncloud.nix
          baseContainerModule
        ];
      in {
        # Expose full NixOS configuration only for one primary architecture
        nixosConfigurations =
          (if system == "x86_64-linux" then {
            owncloud = lib.nixosSystem {
              inherit system;
              modules = owncloudModules;
              specialArgs = {
                inherit pkgsphp74 lib libphp74 phps;
                inputs = { inherit phps nixpkgs; };
              };
            };
          } else { });

        packages = {
          # Docker image build (available under packages.${system}.dockerImage)
            dockerImage = nixos-generators.nixosGenerate {
              inherit system;
              format = "docker";
              modules = owncloudModules;
              specialArgs = {
                inherit pkgsphp74 lib libphp74 phps;
                inputs = { inherit phps nixpkgs; };
              };
            };

          # Simple default package (text file) so `nix build` without attribute works
          default = pkgs.writeTextFile {
            name = "README-owncloud";
            text = ''
              OwnCloud NixOS container flake.

              Build docker image:
                nix build .#packages.${system}.dockerImage
                docker load < result

              Or for x86_64 explicitly:
                nix build .#packages.x86_64-linux.dockerImage

              After loading:
                docker run -it -p 8080:80 owncloud-image-id
            '';
          };
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            nixfmt-rfc-style
          ];
        };
      });
}
