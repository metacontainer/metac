with import ./deps/nixwrt/portable.nix;

rec {
  tigervnc = callPackage (import ./nix/tigervnc.nix) {};
  nim = callPackage (import ./nix/nim.nix) {};
  buildDeb = callPackage (import ./nix/deb.nix) {};

  deps = (import ./deps.nix) {inherit fetchgit;};
  nimArgsBase = toString (map (x: "--path:${toString x}") (builtins.attrValues deps));
  nimArgs = "${nimArgsBase} --path:${deps.backplane}/server";

  metacFiltered = builtins.filterSource
    (path: type: (lib.hasSuffix ".nim" path))
    ./metac;

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
