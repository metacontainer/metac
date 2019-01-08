{pkgs}:

with pkgs;

with rec {
  nimCsources = stdenv.mkDerivation rec {
    name = "nim-csource";
    buildInputs = [];
    src = fetchurl {
      url = "https://github.com/nim-lang/csources/archive/b56e49bbedf62db22eb26388f98262e2948b2cbc.tar.gz";
      sha256 = "76fdf240d4dcb01f751fe5d522ef984d58f86fbff7fa6fbbdc84559d89d9a37a";
    };
    installPhase = ''
      mkdir -p $out/bin
      cp bin/nim $out/bin/nim
    '';
    buildPhase = if builtins.currentSystem == "armv7l-linux" then "make ucpu=arm uos=linux LD=gcc" else "make uos=linux ucpu=amd64 LD=gcc";
    enableParallelBuilding = true;
  };

  nimBootstrap = lastNim: stdenv.mkDerivation rec {
    name = "nim";
    buildInputs = [];
    srcs = fetchurl {
      url = "https://github.com/nim-lang/nim/archive/36e6ca16d1ece106d88fbb951b544b80c360d600.tar.gz";
      sha256 = "023468jh9qhnym8y9q437ibipqvj28nz1ax6g0icc9l3xh8zh4as";
    };
    buildPhase = ''
mkdir -p bin
cp ${lastNim}/bin/nim bin/nim
export XDG_CACHE_HOME=$PWD/cache
./bin/nim c koch
./koch boot -d:release
'';
    installPhase = ''
install -Dt $out/bin bin/* koch
./koch install $out
mv $out/nim/bin/* $out/bin/ && rmdir $out/nim/bin
mv $out/nim/*     $out/     && rmdir $out/nim
'';
  };

  nim = nimBootstrap nimCsources;
};

nim
