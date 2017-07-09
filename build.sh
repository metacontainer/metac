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

get_dep capnp https://github.com/zielmicha/capnp.nim 323bff1190b8208c281a1e6344816a9336918ee3 ''
get_dep cligen https://github.com/c-blake/cligen 493e06338b3fd0b740629823f347b73e5e6853f9 ''
get_dep collections https://github.com/zielmicha/collections.nim 9c4813b67f7a946a62b59d99cb2b4af53f7abb62 ''
get_dep morelinux https://github.com/zielmicha/morelinux 65edae5c9071ad5afc002611ea8f396fee9de000 ''
get_dep reactor https://github.com/zielmicha/reactor.nim 5dff93618c0644255bffee51c67c906788a8836a ''

echo '# reactor.nim requires pthreads
threads: "on"

cc: clang

# enable debugging
passC: "-g"
passL: "-g"

verbosity: "1"
hint[ConvFromXtoItselfNotNeeded]: "off"
hint[XDeclaredButNotUsed]: "off"

#debugger: "native"

threadanalysis: "off"

d:caprpcPrintExceptions
d:caprpcTraceLifetime

d:useRealtimeGC

@if musl:
  cc: gcc
  passL: "-static"
@else:
  cc: clang
  passC: "-fsanitize-trap=null -fsanitize-trap=shift"
@end

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
@else:
  d:useSysAssert
  d:useGcAssert
@end' >> nim.cfg

mkdir -p bin
ln -sf ../.nimenv/nim/bin/nim bin/nim

echo "building metac-vm"; bin/nim c -d:release --out:"$PWD/bin/metac-vm" metac/vm
