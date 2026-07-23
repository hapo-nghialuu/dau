cmake_minimum_required(VERSION 3.16)
project(dau-fcitx5 VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(CTest)

# ---------------------------------------------------------------------------
# Fcitx5 dependencies (addon only; unit tests do not need them)
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
# Build Rust core (staticlib) before linking the addon / tests
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

# Helper: link Rust staticlib + system libs needed by libstd.
function(dau_link_rust_static target_name)
  if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    target_link_libraries(${target_name} PRIVATE
      "-Wl,--whole-archive"
      "${DAU_CORE_LIB}"
      "-Wl,--no-whole-archive"
      dl
      pthread
      m
    )
  elseif(APPLE)
    target_link_libraries(${target_name} PRIVATE
      "${DAU_CORE_LIB}"
      "-framework CoreFoundation"
      "-framework Security"
      dl
      pthread
      m
    )
  else()
    target_link_libraries(${target_name} PRIVATE
      dau_core_static
      dl
      pthread
      m
    )
  endif()
endfunction()

# ---------------------------------------------------------------------------
# Pure typing logic (no fcitx5) — shared by addon + unit tests
# ---------------------------------------------------------------------------
add_library(dau_typing STATIC
  src/rust_bridge.cpp
  src/typing_controller.cpp
  src/strategy_resolver.cpp
)
# PIC required: objects are linked into the MODULE shared library (libdau.so).
set_target_properties(dau_typing PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_dependencies(dau_typing dau_core_rust)
target_include_directories(dau_typing PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${DAU_CORE_INCLUDE}"
)

# ---------------------------------------------------------------------------
# Unit tests: TypingController + StrategyResolver + MockSink (NO fcitx5 link)
# ---------------------------------------------------------------------------
if(BUILD_TESTING)
  add_executable(dau_typing_test
    tests/typing_controller_test.cpp
  )
  add_dependencies(dau_typing_test dau_core_rust)
  target_include_directories(dau_typing_test PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${DAU_CORE_INCLUDE}"
  )
  target_link_libraries(dau_typing_test PRIVATE dau_typing)
  dau_link_rust_static(dau_typing_test)
  add_test(NAME dau_typing_test COMMAND dau_typing_test)

  # Resolver only needs strategy_resolver.cpp + dau_core.h (no Rust link).
  add_executable(dau_strategy_resolver_test
    tests/strategy_resolver_test.cpp
    src/strategy_resolver.cpp
  )
  target_include_directories(dau_strategy_resolver_test PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${DAU_CORE_INCLUDE}"
  )
  add_test(NAME dau_strategy_resolver_test COMMAND dau_strategy_resolver_test)
endif()

# ---------------------------------------------------------------------------
# Addon shared module → libdau.so  (Library=libdau in dau-addon.conf)
# ---------------------------------------------------------------------------
add_library(dau MODULE
  src/keycode_map.cpp
  src/fcitx5_sink.cpp
  src/dau_engine.cpp
  src/dau_engine_config.cpp
  src/dau_addon.cpp
)

add_dependencies(dau dau_core_rust)

target_include_directories(dau PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${DAU_CORE_INCLUDE}"
)

# Explicit Utils include path for <fcitx-utils/text.h> (preedit Text).
# Fcitx5::Utils is also linked below; this guards MODULE builds where
# INTERFACE_INCLUDE_DIRECTORIES of the imported target may not apply alone.
if(TARGET Fcitx5::Utils)
  get_target_property(_DAU_FCITX5_UTILS_INCS Fcitx5::Utils INTERFACE_INCLUDE_DIRECTORIES)
  if(_DAU_FCITX5_UTILS_INCS)
    target_include_directories(dau PRIVATE ${_DAU_FCITX5_UTILS_INCS})
  endif()
endif()
if(DEFINED Fcitx5Utils_INCLUDE_DIRS)
  target_include_directories(dau PRIVATE ${Fcitx5Utils_INCLUDE_DIRS})
endif()
# Debian/Ubuntu layout fallback: libfcitx5utils-dev → /usr/include/Fcitx5/Utils
foreach(_dau_fcitx_inc
    /usr/include/Fcitx5/Utils
    /usr/include/Fcitx5/Core
    /usr/include/Fcitx5/Config
  )
  if(IS_DIRECTORY "${_dau_fcitx_inc}")
    target_include_directories(dau PRIVATE "${_dau_fcitx_inc}")
  endif()
endforeach()

# CMake MODULE default prefix is "lib" → libdau.so on Linux.
set_target_properties(dau PROPERTIES
  OUTPUT_NAME "dau"
  PREFIX "lib"
)

# Fcitx5 shared deps first; Rust staticlib needs whole-archive so C ABI
# symbols and libstd pieces are not dropped when building a MODULE .so.
# System libs (dl/pthread/m) come AFTER the archive so --no-undefined linkers
# can resolve libstd dependencies introduced by whole-archive.
# Fcitx5::Utils is required for fcitx-utils/text.h include path + Text symbols.
target_link_libraries(dau PRIVATE
  Fcitx5::Core
  Fcitx5::Config
  Fcitx5::Utils
  dau_typing
)
dau_link_rust_static(dau)

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

# Shipped per-app strategies (merged under ~/.config/dau/config.toml).
include(GNUInstallDirs)
install(
  FILES "${CMAKE_CURRENT_SOURCE_DIR}/data/profiles.toml"
  DESTINATION "${CMAKE_INSTALL_DATADIR}/dau"
)

# Icons (hicolor theme) → ${CMAKE_INSTALL_PREFIX}/share/icons/hicolor/...
install(
  DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/data/icons/hicolor"
  DESTINATION "${CMAKE_INSTALL_DATADIR}/icons"
)

message(STATUS "Dấu Fcitx5 addon")
message(STATUS "  DAU_ROOT          = ${DAU_ROOT}")
message(STATUS "  DAU_CORE_LIB      = ${DAU_CORE_LIB}")
message(STATUS "  install addon lib = ${_DAU_ADDON_LIBDIR}")
message(STATUS "  install pkg data  = ${FCITX_INSTALL_PKGDATADIR}")
