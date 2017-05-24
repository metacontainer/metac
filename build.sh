#!/bin/sh
set -e
cd "$(dirname "$0")"

if [ -e nimenv.local ]; then
  echo 'nimenv.local exists. You may use `nimenv build` instead of this script.'
  #exit 1
fi

mkdir -p .nimenv/nim
mkdir -p .nimenv/deps

NIMHASH=905df2316262aa2cbacae067acf45fc05c2a71c8c6fde1f2a70c927ebafcfe8a
if ! [ -e .nimenv/nimhash -a \( "$(cat .nimenv/nimhash)" = "$NIMHASH" \) ]; then
  echo "Downloading Nim http://nim-lang.org/download/nim-0.15.2.tar.xz (sha256: $NIMHASH)"
  wget http://nim-lang.org/download/nim-0.15.2.tar.xz -O .nimenv/nim.tar.xz
  if ! [ "$(sha256sum < .nimenv/nim.tar.xz)" = "$NIMHASH  -" ]; then
    echo "verification failed"
    exit 1
  fi
  echo "Unpacking Nim..."
  rm -r .nimenv/nim
  mkdir -p .nimenv/nim
  cd .nimenv/nim
  tar xJf ../nim.tar.xz
  mv nim-*/* .
  echo "Building Nim..."
  make -j$(getconf _NPROCESSORS_ONLN)
  cd ../..
  echo $NIMHASH > .nimenv/nimhash
fi

get_dep() {
  set -e
  cd .nimenv/deps
  name="$1"
  url="$2"
  hash="$3"
  srcpath="$4"
  new=0
  if ! [ -e "$name" ]; then
    git clone --recursive "$url" "$name"
    new=1
  fi
  if ! [ "$(cd "$name" && git rev-parse HEAD)" = "$hash" -a $new -eq 0 ]; then
     cd "$name"
     git fetch --all
     git checkout -q "$hash"
     git submodule update --init
     cd ..
  fi
  cd ../..
  echo "path: \".nimenv/deps/$name$srcpath\"" >> nim.cfg
}

echo "path: \".\"" > nim.cfg

get_dep capnp https://github.com/zielmicha/capnp.nim 105da27725c354b6b9a0faaa99841a53f9e05eb9 ''
get_dep cligen https://github.com/c-blake/cligen 493e06338b3fd0b740629823f347b73e5e6853f9 ''
get_dep collections https://github.com/zielmicha/collections.nim ab4ad35f0cab08e01a16cd54a0c16938a18ba10a ''
get_dep reactor https://github.com/zielmicha/reactor.nim eab8cf8b58e626512159c700e545c80ad88bca20 ''

echo '# reactor.nim requires pthreads
threads: "on"

# enable debugging
passC: "-g"
passL: "-g"

verbosity: "0"
hint[ConvFromXtoItselfNotNeeded]: "off"
hint[XDeclaredButNotUsed]: "off"

debugger: "native"

threadanalysis: "off"

d:caprpcPrintExceptions

@if release:
  gcc.options.always = "-w -fno-strict-overflow"
  gcc.cpp.options.always = "-w -fno-strict-overflow"
  clang.options.always = "-w -fno-strict-overflow"
  clang.cpp.options.always = "-w -fno-strict-overflow"

  passC:"-ffunction-sections -fdata-sections -flto -fPIE -fstack-protector-strong -D_FORTIFY_SOURCE=2"
  passL:"-Wl,--gc-sections -flto -fPIE"

  obj_checks: on
  field_checks: on
  bound_checks: on
@end' >> nim.cfg

mkdir -p bin
ln -sf ../.nimenv/nim/bin/nim bin/nim

echo "building metac-vm"; bin/nim c -d:release --out:"$PWD/bin/metac-vm" metac/vm
