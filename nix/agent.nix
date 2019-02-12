{pkgs, nimArgsBase, nim, metacFiltered}:
with pkgs;

rec {
  vmKernel = (linuxManualConfig rec {
    inherit stdenv;

    version = "4.4.174";
    src = fetchurl {
      url = "mirror://kernel/linux/kernel/v4.x/linux-${version}.tar.xz";
      sha256 = "0fdsxfwhn1xqic56c4aafxw1rdqy7s4w0inmkhcnh98lj3fi2lmy";
    };

    configfile = ./kernel-config;

    # we need the following, or build will fail during postInstall phase
    #extraConfig = { CONFIG_MODULES = "y"; CONFIG_FW_LOADER = "m"; };
  });

  overrideStatic = pkg: pkg.overrideDerivation (attrs: rec {
    buildInputs = attrs.buildInputs ++ [stdenv.glibc.static];
    enableStatic = true;
    preBuild = ''
      makeFlagsArray=(PREFIX="$out"
                      CC="gcc"
                      CFLAGS="${cFlags}"
                      LDFLAGS="${ldFlags}")
    '';
  });

  busyboxStatic = (pkgs.busybox.override {
        enableStatic = true;
        extraConfig = ''
            CONFIG_STATIC y
            CONFIG_INSTALL_APPLET_DONT y
            CONFIG_INSTALL_APPLET_SYMLINKS n
        '';
    });

  vmAgent = stdenv.mkDerivation rec {
    name = "vm-agent";
    buildInputs = [nim stdenv.glibc.static];
    buildPhase = ''
mkdir -p $out/bin
    cp -r ${metacFiltered} metac/
    cp ${../config.nims} config.nims
    touch metac.nimble
    export XDG_CACHE_HOME=$PWD/cache
    nim c -d:release --passl:"-static" --path:. ${nimArgsBase} --out:$out/bin/vm-agent metac/vm_agent.nim
'';
    phases = ["buildPhase"];
  };

  vmInitrd = stdenv.mkDerivation rec {
    name = "vm-initrd.cpio";
    buildInputs = [cpio];
    buildPhase = ''
mkdir -p initrd/bin
cp ${vmAgent}/bin/vm-agent initrd/bin/init
cp ${busyboxStatic}/bin/busybox initrd/bin/busybox
for name in sh mount ifconfig ip; do
    ln -sf /bin/busybox initrd/bin/$name
done
(cd initrd && find ./ | cpio -H newc -o | gzip > $out)

'';
    phases = ["buildPhase"];
  };
}
