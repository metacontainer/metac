with import ../nixwrt/portable.nix;

rec {
  fullDiod = stdenv.mkDerivation rec {
    name = "diod";
    env = buildEnv { name = name; paths = []; };
    buildInputs = [autoconf libtool automake perl ncurses];
    src = ./third-party/diod;
    preConfigurePhases = ["autogen"];
    autogen = "./autogen.sh";
  };

  diod = stdenv.mkDerivation rec {
    name = "diod";
    env = buildEnv { name = name; paths = []; };
    buildInputs = [stdenv.glibc.static];
    src = ./third-party/diod;
    buildPhase = ''gcc ${cFlags} -static -O2 -flto -fPIE -fstack-protector-strong -DHAVE_GETOPT_H -DHAVE_GETOPT_LONG -D_FORTIFY_SOURCE=2 -DMETA_ALIAS='"diod-metac"' -D_GNU_SOURCE -I libnpclient -I libnpfs -I liblsd -I libdiod -DX_LOCALSTATEDIR='""' -Wall diod/diod.c diod/exp.c diod/fid.c diod/ioctx.c diod/ops.c diod/xattr.c libnpclient/chmod.c libnpclient/fid.c libnpclient/fsys.c libnpclient/mkdir.c libnpclient/mount.c libnpclient/mtfsys.c libnpclient/open.c libnpclient/pool.c libnpclient/read.c libnpclient/readdir.c libnpclient/remove.c libnpclient/stat.c libnpclient/walk.c libnpclient/write.c libnpclient/xattr.c liblsd/error.c liblsd/hash.c liblsd/hostlist.c liblsd/list.c liblsd/thread.c libnpfs/conn.c libnpfs/ctl.c libnpfs/error.c libnpfs/fcall.c libnpfs/fdtrans.c libnpfs/fidpool.c libnpfs/fmt.c libnpfs/np.c libnpfs/npstring.c libnpfs/srv.c libnpfs/trans.c libnpfs/user.c libdiod/diod_auth.c libdiod/diod_conf.c libdiod/diod_log.c libdiod/diod_sock.c -pthread -o diod-server ${ldFlags} '';
    installPhase = ''mkdir -p $out/bin; cp diod-server $out/bin'';
  };

  localDeps = {
    reactor = ../reactor;
    capnp = ../capnp;
    collections = ../collections;
    cligen = ../cligen;
    morelinux = ../morelinux;
  };

  nimCsources = stdenv.mkDerivation rec {
    name = "nim-csource";
    buildInputs = [];
    src = fetchurl {
      url = "https://github.com/nim-lang/csources/archive/cdd0f3ff527a6a905fd9e821f381983af45b65de.tar.gz";
      sha256 = "1dmddbayxs4h6a8vwvia85dp6pcq93ijgm260k4j1ib907r6x0fw";
    };
    installPhase = ''
cp bin/nim $out
'';
    enableParallelBuilding = true;
  };

  nimBootstrap = lastNim: stdenv.mkDerivation rec {
    name = "nim";
    buildInputs = [];
    srcs = fetchurl {
      url = "https://github.com/nim-lang/nim/archive/8c0e27e.tar.gz";
      sha256 = "0ib7zn0a9jmgig3f903knyba2gj5sakr41srsq7k9dsljyh4g2zq";
    };
    buildPhase = ''
mkdir -p bin
cp ${lastNim} bin/nim
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

  nimArgs = {deps, args}: ''--path:${deps.reactor} --path:${deps.collections} --path:${deps.capnp} --path:${deps.collections} --path:${deps.cligen} --path:${deps.morelinux} --path:. --nimcache:nix_nimcache ${args}'';

  setupNimProject = options: ''
if find -name nimcache | grep -q '.*'; then
  echo "nimcache exists"
  exit 1
fi
awk '/\[nim\]/,EOF' < ${./nimenv.cfg} | tail -n +2 > nim.cfg
'';

  sftpServer = pkgs.openssh.overrideDerivation (attrs: rec {
    name = "sftp-server";
    buildInputs = attrs.buildInputs ++ [stdenv.glibc.static];
    # TODO: do dynamic linking (patchelf fails on PIC executables)
    buildPhase = ''make CFLAGS="" libssh.a ./openbsd-compat/libopenbsd-compat.a
gcc -ftrapv -D_DEFAULT_SOURCE -D_XOPEN_SOURCE=600 -D_BSD_SOURCE -o sftp-server ${./metac/sftp-server.c} sftp-common.c -Lopenbsd-compat -L. -I.  -fstack-protector-strong -lssh -lopenbsd-compat  -Wl,--gc-sections -static -L${stdenv.glibc.static}/lib'';
    installPhase = ''mkdir -p $out/bin; cp sftp-server $out/bin'';
  });

  bindfd = stdenv.mkDerivation rec {
    name = "bindfd.so";
    buildPhase = ''
gcc -Wall -fPIC -shared ${./metac/bindfd.c} -o $out -ldl
'';
    phases = ["buildPhase"];
  };

  tigervnc = callPackage (import ./nix/tigervnc.nix) {};
  tigervncPortable = portable.make {package = tigervnc; libDir = "tigervnc";};
  agent = callPackage (import ./nix/agent.nix) {inherit setupNimProject nimArgs nim;};

  metac = options: stdenv.mkDerivation rec {
    name = "metac";
    version = "0.0.1";
    buildInputs = [nim gawk sqlite clang];
    buildPhase = ''
cp -r ${./metac} metac
cp -r ${./tests} tests
cp ${./metac.nim} metac.nim
touch metac.nimble
${setupNimProject options}
mkdir -p $out/bin/ $out/share/
${./util/install-systemd.sh} $out
mkdir -p $out/share/metac
cp ${agent.vmInitrd options} $out/share/metac/initrd
cp ${agent.vmKernel}/bzImage $out/share/metac/vmlinuz
cp ${sshfsFuse}/bin/sshfs $out/bin/sshfs
cp ${sftpServer}/bin/sftp-server $out/bin/sftp-server
cp ${tigervnc}/bin/{Xvnc,vncviewer,x0vncserver} $out/bin/
cp ${bindfd} $out/bin/bindfd.so
nim c ${nimArgs options} -d:withSqlite -d:kernelPath="../share/metac/vmlinuz" -d:initrdPath="../share/metac/initrd" --out:$out/bin/metac -d:sshfsPath="sshfs" -d:sftpServerPath="sftp-server" metac/main.nim
'';
    phases = ["buildPhase" "fixupPhase"];
  };

  buildDeb = {pkg, control, postinst}: stdenv.mkDerivation rec {
    name = pkg.name + ".deb";
    buildInputs = [dpkg fakeroot];
    buildPhase = ''
mkdir pkg
cp -a ${pkg} pkg/usr
chmod u+w pkg
mkdir -p pkg/DEBIAN
arch=$(echo $system | cut -d- -f1)
if [ $arch = x86_64 ]; then
  arch=amd64
fi
substituteAll ${control} pkg/DEBIAN/control
cp ${postinst} pkg/DEBIAN/postinst
chmod +x pkg/DEBIAN/postinst
fakeroot -- dpkg-deb --build pkg $out
'';
    phases = ["buildPhase"];
  };

  metacPortable = options: portable.make {
        libDir = "metac";
        mainExe = ["metac"];
        package = metac options;
    };

  metacDeb = options: buildDeb {
    pkg = metacPortable options;
    control = writeText "control" ''Package: metac
Version: ${metacDebug.version}
Section: custom
Priority: optional
Architecture: @arch@
Essential: no
Installed-Size: 1024
Maintainer: Michał Zieliński <michal@zielinscy.org.pl>
Description: MetaContainer - decentralized container orchestration
Dependencies: fuse, ipset, iptables, iproute2
'';
    postinst = writeText "postinst" ''
systemctl daemon-reload
systemctl enable metac.target
systemctl enable metac-bridge
for name in persistence vm fs network computevm desktop; do
    systemctl enable metac-$name
done
'';
  };

  debugOptions = {
    deps = localDeps;
    args = "";
  };

  releaseOptions = {
    deps = localDeps;
    args = "-d:release";
  };

  metacDebRelease = metacDeb releaseOptions;
  metacDebDebug = metacDeb debugOptions;
  metacDebug = metac debugOptions;
  vmAgentDebug = agent.vmAgent debugOptions;
  metacPortableDebug = metacPortable debugOptions;
}
