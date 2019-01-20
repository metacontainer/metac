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

  webui_node_modules = fetchzip {
    url = "https://cdn.atomshare.net/012c6414154eeb78c99ea7382c50980dc44fb204/node_modules.tar.xz";
    name = "node_modules";
    sha256 = "1hk0q3hsrymd77x40dmvv4qmr8xmqv76s6kd1nmhp13jrs3bg0r7";
  };

  webui = stdenv.mkDerivation rec {
    name = "metac";

    buildInputs = [nodejs];
    phases = ["buildPhase"];

    buildPhase = ''
    cp ${./webui/tsconfig.json} tsconfig.json
    cp ${./webui/webpack.config.js} webpack.config.js
    cp -r ${./webui/src} src
    cp -r ${./webui/node_modules}/ node_modules
    node ./node_modules/.bin/webpack --mode production
    mkdir -p $out/share/webui
    cp node_modules/react/umd/react.production.min.js $out/share/webui/react.min.js
    cp node_modules/react-dom/umd/react-dom.production.min.js $out/share/webui/react-dom.min.js
    cp dist/index.js{,.map} $out/share/webui/
    '';
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
    nim c -d:release -d:helpersPath=. -d:webuiPath=../../share/webui --path:. ${nimArgs} --out:$out/bin/metac metac/cli.nim'';
  };

  metacWithDeps = stdenv.mkDerivation rec {
    name = "metac";
    version = metac.version;

    phases = ["installPhase"];

    installPhase = ''
      mkdir -p $out/bin $out/share
      cp ${metac}/bin/* $out/bin
      cp ${tigervnc}/bin/* $out/bin
      cp ${sftpServer}/bin/* $out/bin
      cp ${sshfsFuse}/bin/sshfs $out/bin
      cp -r ${webui}/share/webui $out/share/webui
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
