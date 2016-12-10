cmake_minimum_required (VERSION 2.6)
project(metac)

set(OPT_COMMON "-D_GLIBCXX_DEBUG")
set(CMAKE_CXX_FLAGS "-std=c++14 -g -Wall -fdiagnostics-color -Og ${OPT_COMMON} -Wno-literal-suffix")
set(CMAKE_C_FLAGS "-std=c11 -D_GNU_SOURCE")
set(CMAKE_EXE_LINKER_FLAGS "-rdynamic -lrt ${OPT_COMMON}")

include_directories(${CMAKE_SOURCE_DIR})

add_library(metac STATIC
  metac/metac.capnp.c++
  metac/ostools.c++
  metac/stlfixes.c++
  metac/metac.c++)

set(METAC_LIBS metac capnp capnp-rpc kj kj-async)

add_executable(metac-bridge
  metac/bridge.c++)

target_link_libraries(metac-bridge ${METAC_LIBS})
