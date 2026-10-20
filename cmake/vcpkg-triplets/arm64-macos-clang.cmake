set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
# LGPL: openal-soft must be dynamically linked so users can replace the implementation
if(PORT STREQUAL "openal-soft")
    set(VCPKG_LIBRARY_LINKAGE dynamic)
endif()

set(VCPKG_CMAKE_SYSTEM_NAME Darwin)
set(VCPKG_OSX_ARCHITECTURES arm64)

# Keep dependency binaries compatible with the requested deployment target,
# including when building on a newer Mac. Track the value in vcpkg's ABI cache.
list(APPEND VCPKG_ENV_PASSTHROUGH MACOSX_DEPLOYMENT_TARGET)
if(DEFINED ENV{MACOSX_DEPLOYMENT_TARGET} AND NOT "$ENV{MACOSX_DEPLOYMENT_TARGET}" STREQUAL "")
    set(VCPKG_OSX_DEPLOYMENT_TARGET "$ENV{MACOSX_DEPLOYMENT_TARGET}")
endif()

set(VCPKG_CMAKE_CONFIGURE_OPTION -DCMAKE_BUILD_TYPE=RelWithDebInfo)
