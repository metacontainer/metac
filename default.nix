with import ./deps/nixwrt/portable.nix;

rec {
  tigervnc = callPackage (import ./nix/tigervnc.nix) {};
  nim = callPackage (import ./nix/nim.nix) {};
  autoconf = pkgs.autoconf;

  deps = (import ./deps.nix) {inherit fetchgit;};
  nimArgsBase = toString (map (x: "--path:${toString x}") (builtins.attrValues deps));
  nimArgs = "${nimArgsBase} --path:${deps.backplane}/server";

  metacFiltered = builtins.filterSource
    (path: type: (lib.hasSuffix ".nim" path))
    ./metac;

  metac = stdenv.mkDerivation rec {
    name = "metac";
    version = "2019.01.01.1";
    buildInputs = [nim libsodium];

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

}
