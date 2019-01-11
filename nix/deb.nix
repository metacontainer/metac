{stdenv, dpkg, fakeroot}:
{pkg, control, postinst}: stdenv.mkDerivation rec {
  name = "${pkg.name}-${pkg.version}.deb";
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
if [ $arch = armv7l ]; then
  arch=armhf
fi
substituteAll ${control} pkg/DEBIAN/control
cp ${postinst} pkg/DEBIAN/postinst
chmod +x pkg/DEBIAN/postinst
fakeroot -- dpkg-deb --build pkg $out
'';
  phases = ["buildPhase"];
}
