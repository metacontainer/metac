{pkgs, setupNimProject, nimArgs, nim, metacSource}:
with pkgs.newGlibcPkgs;

rec {
  vmKernel = (buildLinux rec {
    version = "4.4.110";
    src = fetchurl {
      url = "mirror://kernel/linux/kernel/v4.x/linux-${version}.tar.xz";
      sha256 = "d099175aac5678e6cad2f23cd56ed22a2857143c0c18489390c95ba8c441db58";
    };
    configfile = ./kernel-config;
    # we need the following, or build will fail during postInstall phase
    config = { CONFIG_MODULES = "y"; CONFIG_FW_LOADER = "m"; };
  });

  #cFlags = "-nostdinc -isystem ${musl}/include -ffunction-sections -fdata-sections";
  #ldFlags = "-nostdlib -L${musl}/lib ${musl}/lib/crt1.o ${musl}/lib/crti.o ${musl}/lib/crtn.o -lc -lm -static";

  # musl crashes diod, compile with glibc for now
  cFlags = "-DSTATIC_GLIBC";
  ldFlags = "-static -lm";
  staticNimFlags = ''--passl:"${ldFlags}" --passc:"${cFlags}"'';

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

  sqliteStatic = overrideStatic pkgs.sqlite;
  glibStatic = overrideStatic pkgs.glib;
  fuseStatic = overrideStatic pkgs.fuse;
  sshfs = (import ./sshfs.nix) {inherit pkgs glibStatic fuseStatic;};

  vmAgent = options: stdenv.mkDerivation rec {
    name = "vm-agent";
    buildInputs = [nim gawk stdenv.glibc.static clang];
    buildPhase = ''
cp -r ${metacSource}/* ./
chmod -R u+w .
${setupNimProject}
find
echo nim c ${nimArgs options} ${staticNimFlags} --out:$out metac/compute_agent.nim
nim c ${nimArgs options} ${staticNimFlags} --out:$out metac/compute_agent.nim
'';
    phases = ["buildPhase"];
  };

  vmInitrd = options: stdenv.mkDerivation rec {
    name = "vm-initrd.cpio";
    buildInputs = [cpio];
    buildPhase = ''
mkdir -p initrd/bin
cp ${vmAgent options} initrd/bin/init
cp ${busyboxStatic}/bin/busybox initrd/bin/busybox
for name in sh mount ifconfig ip; do
    ln -sf /bin/busybox initrd/bin/$name
done
cp ${sshfs}/bin/sshfs initrd/bin/metac-sshfs
cp ${fuseStatic}/bin/fusermount initrd/bin/fusermount
(cd initrd && find ./ | cpio -H newc -o | gzip > $out)

'';
    phases = ["buildPhase"];
  };
}
