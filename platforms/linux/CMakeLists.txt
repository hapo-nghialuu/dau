cmake_minimum_required(VERSION 3.16)
project(dau-fcitx5 VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ---------------------------------------------------------------------------
# Fcitx5 dependencies
# ---------------------------------------------------------------------------
find_package(Fcitx5Core REQUIRED)
find_package(Fcitx5Config REQUIRED)
find_package(Fcitx5Utils REQUIRED)

# Compiler flags compatible with Fcitx 5 (C++17, warnings, etc.)
if(EXISTS "${FCITX_INSTALL_CMAKECONFIG_DIR}/Fcitx5Utils/Fcitx5CompilerSettings.cmake")
  include("${FCITX_INSTALL_CMAKECONFIG_DIR}/Fcitx5Utils/Fcitx5CompilerSettings.cmake")
endif()

# ---------------------------------------------------------------------------
# Paths: repo root = platforms/linux/../..
# ---------------------------------------------------------------------------
get_filename_component(DAU_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
set(DAU_CORE_DIR "${DAU_ROOT}/core")
set(DAU_CORE_INCLUDE "${DAU_CORE_DIR}/include")
set(DAU_CORE_LIB "${DAU_CORE_DIR}/target/release/libdau_core.a")

# ---------------------------------------------------------------------------
# Build Rust core (staticlib) before linking the addon
# ---------------------------------------------------------------------------
find_program(CARGO_EXECUTABLE cargo REQUIRED)

add_custom_command(
  OUTPUT "${DAU_CORE_LIB}"
  COMMAND
    ${CMAKE_COMMAND} -E env
      "CARGO_TARGET_DIR=${DAU_CORE_DIR}/target"
      ${CARGO_EXECUTABLE} build --release
        --manifest-path "${DAU_CORE_DIR}/Cargo.toml"
  WORKING_DIRECTORY "${DAU_CORE_DIR}"
  COMMENT "Building dau-core (Rust staticlib → libdau_core.a)"
  VERBATIM
  # Re-run when core sources change (best-effort; cargo itself is authoritative).
  DEPENDS
    "${DAU_CORE_DIR}/Cargo.toml"
    "${DAU_CORE_DIR}/src/lib.rs"
    "${DAU_CORE_DIR}/src/ffi.rs"
    "${DAU_CORE_INCLUDE}/dau_core.h"
)

add_custom_target(dau_core_rust DEPENDS "${DAU_CORE_LIB}")

add_library(dau_core_static STATIC IMPORTED GLOBAL)
set_target_properties(dau_core_static PROPERTIES
  IMPORTED_LOCATION "${DAU_CORE_LIB}"
)
add_dependencies(dau_core_static dau_core_rust)

# ---------------------------------------------------------------------------
# Addon shared module → libdau.so  (Library=libdau in dau-addon.conf)
# ---------------------------------------------------------------------------
add_library(dau MODULE
  src/rust_bridge.cpp
  src/keycode_map.cpp
  src/dau_engine.cpp
  src/dau_addon.cpp
)

add_dependencies(dau dau_core_rust)

target_include_directories(dau PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${DAU_CORE_INCLUDE}"
)

# CMake MODULE default prefix is "lib" → libdau.so on Linux.
set_target_properties(dau PROPERTIES
  OUTPUT_NAME "dau"
  PREFIX "lib"
)

# Fcitx5 shared deps first; Rust staticlib needs whole-archive so C ABI
# symbols and libstd pieces are not dropped when building a MODULE .so.
# System libs (dl/pthread/m) come AFTER the archive so --no-undefined linkers
# can resolve libstd dependencies introduced by whole-archive.
target_link_libraries(dau PRIVATE
  Fcitx5::Core
  Fcitx5::Config
  Fcitx5::Utils
)

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  target_link_libraries(dau PRIVATE
    "-Wl,--whole-archive"
    "${DAU_CORE_LIB}"
    "-Wl,--no-whole-archive"
    dl
    pthread
    m
  )
else()
  target_link_libraries(dau PRIVATE
    dau_core_static
    dl
    pthread
    m
  )
endif()

# ---------------------------------------------------------------------------
# Install
#   libdau.so  → ${FCITX_INSTALL_LIBDIR}/fcitx5
#   dau.conf   → ${FCITX_INSTALL_PKGDATADIR}/addon        (from dau-addon.conf)
#   dau.conf   → ${FCITX_INSTALL_PKGDATADIR}/inputmethod  (IM entry)
# ---------------------------------------------------------------------------
if(DEFINED FCITX_INSTALL_ADDONDIR)
  set(_DAU_ADDON_LIBDIR "${FCITX_INSTALL_ADDONDIR}")
else()
  set(_DAU_ADDON_LIBDIR "${FCITX_INSTALL_LIBDIR}/fcitx5")
endif()

install(TARGETS dau DESTINATION "${_DAU_ADDON_LIBDIR}")

install(
  FILES "${CMAKE_CURRENT_SOURCE_DIR}/data/dau-addon.conf"
  RENAME "dau.conf"
  DESTINATION "${FCITX_INSTALL_PKGDATADIR}/addon"
)

install(
  FILES "${CMAKE_CURRENT_SOURCE_DIR}/data/dau.conf"
  DESTINATION "${FCITX_INSTALL_PKGDATADIR}/inputmethod"
)

message(STATUS "Dấu Fcitx5 addon")
message(STATUS "  DAU_ROOT          = ${DAU_ROOT}")
message(STATUS "  DAU_CORE_LIB      = ${DAU_CORE_LIB}")
message(STATUS "  install addon lib = ${_DAU_ADDON_LIBDIR}")
message(STATUS "  install pkg data  = ${FCITX_INSTALL_PKGDATADIR}")
