with import ./deps/nixwrt/portable.nix;

rec {
  tigervnc = callPackage (import ./nix/tigervnc.nix) {};
  nim = callPackage (import ./nix/nim.nix) {};
  buildDeb = callPackage (import ./nix/deb.nix) {};
  sshfsFuse = pkgs.sshfsFuse;

  deps = (import ./deps.nix) {inherit fetchgit;};
  nimArgsBase = toString (map (x: "--path:${toString x}") (builtins.attrValues deps));
  nimArgs = "${nimArgsBase} --path:${deps.backplane}/server";

  metacFiltered = builtins.filterSource
    (path: type: (lib.hasSuffix ".nim" path))
    ./metac;

  sftpServer = pkgs.openssh.overrideDerivation (attrs: rec {
    name = "sftp-server";
    buildInputs = attrs.buildInputs ++ [stdenv.glibc.static];
    # (???) TODO: do dynamic linking (patchelf fails on PIC executables)
    buildPhase = ''make CFLAGS='-fPIC' libssh.a ./openbsd-compat/libopenbsd-compat.a
gcc -fPIC -ftrapv -D_DEFAULT_SOURCE -D_XOPEN_SOURCE=600 -D_BSD_SOURCE -o sftp-server ${./metac/sftp-server.c} sftp-common.c -Lopenbsd-compat -L. -I.  -fstack-protector-strong -lssh -lopenbsd-compat  -Wl,--gc-sections'';
    installPhase = ''mkdir -p $out/bin; cp sftp-server $out/bin'';
  });

  SDL2 = callPackage (import "${pkgs.repo}/pkgs/development/libraries/SDL2") {
    inherit (darwin.apple_sdk.frameworks) AudioUnit Cocoa CoreAudio CoreServices ForceFeedback OpenGL;
    openglSupport = false;
    alsaSupport = true;
    x11Support = false;
    # waylandSupport = false;
    udevSupport = false;
    pulseaudioSupport = false;
  };

  metac = stdenv.mkDerivation rec {
    name = "metac";
    version = "2019.01.11.1";
    buildInputs = [nim libsodium SDL2 gtk3 libopus];

    phases = ["buildPhase" "fixupPhase"];

    buildPhase = ''mkdir -p $out/bin
    cp -r ${metacFiltered} metac/
    cp ${./config.nims} config.nims
    touch metac.nimble
    export XDG_CACHE_HOME=$PWD/cache
    nim c -d:release -d:helpersPath=. --path:. ${nimArgs} --out:$out/bin/metac metac/cli.nim'';
  };

  metacWithDeps = stdenv.mkDerivation rec {
    name = "metac";
    version = metac.version;

    phases = ["installPhase"];

    installPhase = ''
      mkdir -p $out/bin
      cp ${metac}/bin/* $out/bin
      cp ${tigervnc}/bin/* $out/bin
      cp ${sftpServer}/bin/* $out/bin
      cp ${sshfsFuse}/bin/sshfs $out/bin
    '';
  };

  metacPortable = (portable.make {
    libDir = "metac";
    mainExe = ["metac"];
    package = metacWithDeps;
  }).overrideAttrs (attrs: rec {
    fixupPhase = '' '';
  });

  metacDeb = buildDeb {
    pkg = metacPortable;
    control = writeText "control" ''Package: metac
Version: ${metac.version}
Section: custom
Priority: optional
Architecture: @arch@
Essential: no
Installed-Size: 1024
Maintainer: Michał Zieliński <michal@zielinscy.org.pl>
Description: MetaContainer - share access to your files/desktops/USB devices securely
Depends: fuse, ipset, iptables, iproute2
Recommends: pulseaudio
'';
    postinst = writeText "postinst" ''
'';
  };
}
