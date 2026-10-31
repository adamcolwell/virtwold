{
  description = "Wake-on-LAN daemon for libvirt virtual machines";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.buildGoModule {
          pname = "virtwold";
          version = "0-unstable-${self.shortRev or "dev"}";

          src = ./.;
          vendorHash = "sha256-qJ+mwdLLOXmIqGHp+eiNy9qUS7ULNwn0PHoE7RNI/U8=";

          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = [
            pkgs.libpcap
            pkgs.libvirt
          ];

          meta = {
            description = "Wake-on-LAN daemon for libvirt virtual machines";
            homepage = "https://github.com/ScottESanDiego/virtwold";
            license = pkgs.lib.licenses.bsd2;
            mainProgram = "virtwold";
            platforms = pkgs.lib.platforms.linux;
          };
        };
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = pkgs.lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.go
            pkgs.gotools
            pkgs.pkg-config
            pkgs.libpcap
            pkgs.libvirt
          ];
        };
      });

      nixosModules.default =
        { config, lib, pkgs, ... }:
        let
          cfg = config.services.virtwold;
        in
        {
          options.services.virtwold = {
            enable = lib.mkEnableOption "virtwold, a wake-on-LAN daemon for libvirt VMs";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              defaultText = lib.literalExpression "virtwold.packages.\${system}.default";
              description = "virtwold package to run.";
            };

            interfaces = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [ "br0" ];
              description = "Network interfaces to listen on. One service is started per interface.";
            };

            libvirtUri = lib.mkOption {
              type = lib.types.str;
              default = "qemu+tcp:///system";
              example = "qemu:///system";
              description = "libvirt connection URI.";
            };
          };

          config = lib.mkIf cfg.enable {
            assertions = [
              {
                assertion = cfg.interfaces != [ ];
                message = "services.virtwold.interfaces must contain at least one interface";
              }
            ];

            systemd.services = lib.listToAttrs (
              map (iface: {
                name = "virtwold-${iface}";
                value = {
                  description = "libvirt wake-on-LAN daemon (${iface})";
                  after = [
                    "network.target"
                    "libvirtd.service"
                  ];
                  wants = [ "libvirtd.service" ];
                  wantedBy = [ "multi-user.target" ];
                  serviceConfig = {
                    ExecStart = "${lib.getExe cfg.package} --interface ${iface} --libvirturi ${cfg.libvirtUri}";
                    Restart = "on-failure";
                    RestartSec = 30;
                  };
                };
              }) cfg.interfaces
            );
          };
        };
    };
}
