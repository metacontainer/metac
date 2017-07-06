with (let
      # Pin a revision from Nixpkgs repo for reproducible builds.
      _nixpkgs = import <nixpkgs> { };
      repo = _nixpkgs.fetchFromGitHub { owner = "NixOS"; repo = "nixpkgs"; rev = "ec9a23332f06eca2996b15dfd83abfd54a27437a"; sha256 = "09d225y0a4ldx08b5rfhy7jk4qp0nj4q7xsjb49hvb5an79xmgdl"; };
      in import repo) {};

rec {

  nim = pkgs.nim;

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
    buildInputs = [];
    src = ./third-party/diod;
    buildPhase = ''gcc -O2 -flto -fPIE -fstack-protector-strong -DHAVE_GETOPT_H -DHAVE_GETOPT_LONG -D_FORTIFY_SOURCE=2 -DMETA_ALIAS='"diod-metac"' -D_GNU_SOURCE -I libnpclient -I libnpfs -I liblsd -I libdiod -DX_LOCALSTATEDIR='""' -Wall diod/diod.c diod/exp.c diod/fid.c diod/ioctx.c diod/ops.c diod/xattr.c libnpclient/chmod.c libnpclient/fid.c libnpclient/fsys.c libnpclient/mkdir.c libnpclient/mount.c libnpclient/mtfsys.c libnpclient/open.c libnpclient/pool.c libnpclient/read.c libnpclient/readdir.c libnpclient/remove.c libnpclient/stat.c libnpclient/walk.c libnpclient/write.c libnpclient/xattr.c liblsd/error.c liblsd/hash.c liblsd/hostlist.c liblsd/list.c liblsd/thread.c libnpfs/conn.c libnpfs/ctl.c libnpfs/error.c libnpfs/fcall.c libnpfs/fdtrans.c libnpfs/fidpool.c libnpfs/fmt.c libnpfs/np.c libnpfs/npstring.c libnpfs/srv.c libnpfs/trans.c libnpfs/user.c libdiod/diod_auth.c libdiod/diod_conf.c libdiod/diod_log.c libdiod/diod_sock.c -pthread -o diod-server'';
    installPhase = ''mkdir -p $out/bin; cp diod-server $out/bin'';
  };

  #vmKernel = linuxPackages_4_4.kernel.overrideAttrs (attrs: {
  #  configfile = ./.config;
  #});

  vmKernel = buildLinux rec {
    version = "4.4.76";
    src = fetchurl {
      url = "mirror://kernel/linux/kernel/v4.x/linux-${version}.tar.xz";
      sha256 = "180mngyar7ky2aiaszmgfqpfvwi0kxcym8j3ifflzggwqjkgrrki";
    };
    configfile = ./kernel-config;
    # we need the following, or build will fail during postInstall phase
    config = { CONFIG_MODULES = "y"; CONFIG_FW_LOADER = "m"; };
  };
}
