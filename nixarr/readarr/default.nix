{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.nixarr.readarr;
  nixarr = config.nixarr;
  dnsServers = config.lib.vpn.dnsServers;
in {
  options.nixarr.readarr = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = lib.mdDoc "Enable readarr";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/nixarr/readarr";
      description = lib.mdDoc "The state directory for readarr";
    };

    useVpn = mkOption {
      type = types.bool;
      default = false;
      description = lib.mdDoc "Use VPN with prowlarr";
    };
  };

  config = mkIf cfg.enable {
    services.readarr = {
      enable = cfg.enable;
      user = "readarr";
      group = "media";
      dataDir = cfg.stateDir;
    };

    util.vpnnamespace.portMappings = [
      (
        mkIf cfg.useVpn {
          From = defaultPort;
          To = defaultPort;
        }
      )
    ];

    containers.readarr = mkIf cfg.useVpn {
      autoStart = true;
      ephemeral = true;
      extraFlags = ["--network-namespace-path=/var/run/netns/wg"];

      bindMounts = {
        "${nixarr.mediaDir}".isReadOnly = false;
        "${cfg.stateDir}".isReadOnly = false;
      };

      config = {
        users.groups.media = {
          gid = config.users.groups.media.gid;
        };
        users.users.readarr = {
          uid = lib.mkForce config.users.users.readarr.uid;
          isSystemUser = true;
          group = "media";
        };

        # Use systemd-resolved inside the container
        # Workaround for bug https://github.com/NixOS/nixpkgs/issues/162686
        networking.useHostResolvConf = lib.mkForce false;
        services.resolved.enable = true;
        networking.nameservers = dnsServers;

        services.readarr = {
          enable = true;
          group = "media";
          dataDir = "${cfg.stateDir}";
        };

        system.stateVersion = "23.11";
      };
    };

    services.nginx = mkIf cfg.useVpn {
      enable = true;

      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."127.0.0.1:${builtins.toString defaultPort}" = {
        listen = [
          {
            addr = "0.0.0.0";
            port = defaultPort;
          }
        ];
        locations."/" = {
          recommendedProxySettings = true;
          proxyWebsockets = true;
          proxyPass = "http://192.168.15.1:${builtins.toString defaultPort}";
        };
      };
    };
  };
}