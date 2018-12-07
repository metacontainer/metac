{pkgs, glibStatic, fuseStatic}:
with pkgs;

stdenv.mkDerivation rec {
    version = "2.9";
    name = ''sshfs-fuse-${version}'';
    enableStatic = true;

    config = ''/* Name of package */
#define PACKAGE "sshfs"

/* Define to the address where bug reports for this package should be sent. */
#define PACKAGE_BUGREPORT ""

/* Define to the full name of this package. */
#define PACKAGE_NAME "sshfs"

/* Define to the full name and version of this package. */
#define PACKAGE_STRING "sshfs 2.9"

/* Define to the one symbol short name of this package. */
#define PACKAGE_TARNAME "sshfs"

/* Define to the home page for this package. */
#define PACKAGE_URL ""

/* Define to the version of this package. */
#define PACKAGE_VERSION "2.9"

/* Compile ssh NODELAY workaround */
/* #undef SSH_NODELAY_WORKAROUND */

/* Version number of package */
#define VERSION "2.9"

#define IDMAP_DEFAULT "none"
'';

    buildPhase = ''
echo "$config" > config.h
gcc -D_FILE_OFFSET_BITS=64 cache.c sshfs.c -DFUSE_USE_VERSION=26 -D_REENTRANT -I${fuseStatic}/include -I${fuseStatic}/include/fuse -I${glibStatic.dev}/include/glib-2.0 -I${glibStatic}/lib/glib-2.0/include -g -O2 -Wall -W -o sshfs  -L${fuseStatic}/lib -L${glibStatic}/lib -lfuse -lgthread-2.0 -pthread -lglib-2.0 -ldl -static
'';
    installPhase = ''mkdir -p $out/bin; cp sshfs $out/bin'';

    phases = ["unpackPhase" "buildPhase" "installPhase"];

    src = fetchFromGitHub {
      repo = "sshfs";
      owner = "libfuse";
      rev = ''sshfs-${version}'';
      sha256 = "1n0cq72ps4dzsh72fgfprqn8vcfr7ilrkvhzpy5500wjg88diapv";
    };

    buildInputs = [ pkgconfig glibStatic fuseStatic autoreconfHook stdenv.glibc.static ];
}
