{ buildEnv
, dockerTools
, runCommand
, writeText

, bash
, coreutils
, nixStatic
, pigz

, pkgsStatic
}:

let
  wslConf = writeText "wsl.conf" ''
    [user]
    default = nix

    # [automount]
    # mountFsTab = false
  '';

  passwd = writeText "passwd" ''
    root:x:0:0:System administrator:/root:/bin/sh
    nix:x:1000:1000:Nix:/home/nix:/bin/sh
  '';

  group = writeText "group" ''
    root:x:0:
    nix:x:1000:
  '';

  nsswitch = writeText "nsswitch" ''
    hosts: files dns
  '';

  nixConf = writeText "nix.conf" ''
    experimental-features = nix-command flakes
  '';

  dockerImage = dockerTools.buildImageWithNixDb {
    name = "nix";
    tag = "latest";

    copyToRoot = buildEnv {
      name = "nix-image";
      pathsToLink = [ "/bin" "/etc" ];
      paths = [
        pkgsStatic.busybox
        nixStatic

        # Closure of this is 500k so not to worried about shrinking it.
        # Busybox is ~1MB, and the bulk of the image size is nixStatic
        dockerTools.caCertificates
      ];
    };

    extraCommands = ''
      chown -R 1000 nix
    '';

    # Need to turn this into a "root layer" due to a quirk of the dockerTools system.
    # If it were a "pure layer", then everything in it would get rsynced with --owner and --group
    # flags, so we wouldn't be able to chown anything
    runAsRoot = ''
      cp "${wslConf}" /etc/wsl.conf
      cp "${passwd}" /etc/passwd
      cp "${group}" /etc/group

      # For binaries that insist on using nss to look up username/groups (like nginx).
      # See fakeNss from Nixpkgs
      cp "${nsswitch}" /etc/nsswitch.conf
      mkdir -p /var/empty

      touch /etc/fstab

      mkdir -p /etc/nix
      cp "${nixConf}" /etc/nix/nix.conf

      mkdir -p /usr/bin
      ln -s ${pkgsStatic.busybox}/bin/env /usr/bin/env

      mkdir -p /home/nix

      chown 1000:1000 /home/nix
    '';
  };

in

runCommand "nix-image-docker.tar.gz" { buildInputs = [pigz]; } ''
  mkdir temp
  cd temp
  tar -zxvf "${dockerImage}"

  LAYER_TAR=$(find . -name layer.tar)

  cat "$LAYER_TAR" | pigz > $out
''
