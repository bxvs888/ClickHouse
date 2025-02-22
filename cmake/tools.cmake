# Compiler

if (CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    set (COMPILER_GCC 1)
elseif (CMAKE_CXX_COMPILER_ID MATCHES "AppleClang")
    set (COMPILER_CLANG 1) # Safe to treat AppleClang as a regular Clang, in general.
elseif (CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    set (COMPILER_CLANG 1)
else ()
    message (FATAL_ERROR "Compiler ${CMAKE_CXX_COMPILER_ID} is not supported")
endif ()

# Print details to output
execute_process(COMMAND ${CMAKE_CXX_COMPILER} --version OUTPUT_VARIABLE COMPILER_SELF_IDENTIFICATION OUTPUT_STRIP_TRAILING_WHITESPACE)
message (STATUS "Using compiler:\n${COMPILER_SELF_IDENTIFICATION}")

# Require minimum compiler versions
set (CLANG_MINIMUM_VERSION 15)
set (XCODE_MINIMUM_VERSION 12.0)
set (APPLE_CLANG_MINIMUM_VERSION 12.0.0)
set (GCC_MINIMUM_VERSION 11)

if (COMPILER_GCC)
    message (FATAL_ERROR "Compilation with GCC is unsupported. Please use Clang instead.")

    if (CMAKE_CXX_COMPILER_VERSION VERSION_LESS ${GCC_MINIMUM_VERSION})
        message (FATAL_ERROR "Compilation with GCC version ${CMAKE_CXX_COMPILER_VERSION} is unsupported, the minimum required version is ${GCC_MINIMUM_VERSION}.")
    endif ()

elseif (COMPILER_CLANG)
    if (CMAKE_CXX_COMPILER_ID MATCHES "AppleClang")
        # (Experimental!) Specify "-DALLOW_APPLECLANG=ON" when running CMake configuration step, if you want to experiment with using it.
        if (NOT ALLOW_APPLECLANG AND NOT DEFINED ENV{ALLOW_APPLECLANG})
            message (FATAL_ERROR "Compilation with AppleClang is unsupported. Please use vanilla Clang, e.g. from Homebrew.")
        endif ()

        # For a mapping between XCode / AppleClang / vanilla Clang versions, see https://en.wikipedia.org/wiki/Xcode
        if (CMAKE_CXX_COMPILER_VERSION VERSION_LESS ${APPLE_CLANG_MINIMUM_VERSION})
            message (FATAL_ERROR "Compilation with AppleClang version ${CMAKE_CXX_COMPILER_VERSION} is unsupported, the minimum required version is ${APPLE_CLANG_MINIMUM_VERSION} (Xcode ${XCODE_MINIMUM_VERSION}).")
        endif ()
    else ()
        if (CMAKE_CXX_COMPILER_VERSION VERSION_LESS ${CLANG_MINIMUM_VERSION})
            message (FATAL_ERROR "Compilation with Clang version ${CMAKE_CXX_COMPILER_VERSION} is unsupported, the minimum required version is ${CLANG_MINIMUM_VERSION}.")
        endif ()
    endif ()
endif ()

# Linker

string (REGEX MATCHALL "[0-9]+" COMPILER_VERSION_LIST ${CMAKE_CXX_COMPILER_VERSION})
list (GET COMPILER_VERSION_LIST 0 COMPILER_VERSION_MAJOR)

# Example values: `lld-10`
option (LINKER_NAME "Linker name or full path")

if (LINKER_NAME MATCHES "gold")
    message (FATAL_ERROR "Linking with gold is unsupported. Please use lld.")
endif ()

if (NOT LINKER_NAME)
    if (COMPILER_GCC)
        find_program (LLD_PATH NAMES "ld.lld")
    elseif (COMPILER_CLANG)
        # llvm lld is a generic driver.
        # Invoke ld.lld (Unix), ld64.lld (macOS), lld-link (Windows), wasm-ld (WebAssembly) instead
        if (OS_LINUX)
            if (NOT ARCH_S390X) # s390x doesnt support lld
                find_program (LLD_PATH NAMES "ld.lld-${COMPILER_VERSION_MAJOR}" "ld.lld")
            endif ()
        elseif (OS_DARWIN)
            find_program (LLD_PATH NAMES "ld64.lld-${COMPILER_VERSION_MAJOR}" "ld64.lld")
        endif ()
    endif ()
    if (OS_LINUX OR OS_DARWIN)
        if (LLD_PATH)
            if (COMPILER_GCC)
                # GCC driver requires one of supported linker names like "lld".
                set (LINKER_NAME "lld")
            else ()
                # Clang driver simply allows full linker path.
                set (LINKER_NAME ${LLD_PATH})
            endif ()
        endif ()
    endif()
endif()

if (LINKER_NAME)
    find_program (LLD_PATH NAMES ${LINKER_NAME})
    if (NOT LLD_PATH)
        message (FATAL_ERROR "Using linker ${LINKER_NAME} but can't find its path.")
    endif ()
    if (COMPILER_CLANG)
        # This a temporary quirk to emit .debug_aranges with ThinLTO, can be removed after upgrade to clang-16
        set (LLD_WRAPPER "${CMAKE_CURRENT_BINARY_DIR}/ld.lld")
        configure_file ("${CMAKE_CURRENT_SOURCE_DIR}/cmake/ld.lld.in" "${LLD_WRAPPER}" @ONLY)

        set (CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} --ld-path=${LLD_WRAPPER}")
    else ()
        set (CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fuse-ld=${LINKER_NAME}")
    endif ()

endif ()

if (LINKER_NAME)
    message(STATUS "Using linker: ${LINKER_NAME}")
else()
    message(STATUS "Using linker: <default>")
endif()

# Archiver

if (COMPILER_GCC)
    find_program (LLVM_AR_PATH NAMES "llvm-ar" "llvm-ar-15" "llvm-ar-14" "llvm-ar-13" "llvm-ar-12")
else ()
    find_program (LLVM_AR_PATH NAMES "llvm-ar-${COMPILER_VERSION_MAJOR}" "llvm-ar")
endif ()

if (LLVM_AR_PATH)
    set (CMAKE_AR "${LLVM_AR_PATH}")
endif ()

message(STATUS "Using archiver: ${CMAKE_AR}")

# Ranlib

if (COMPILER_GCC)
    find_program (LLVM_RANLIB_PATH NAMES "llvm-ranlib" "llvm-ranlib-15" "llvm-ranlib-14" "llvm-ranlib-13" "llvm-ranlib-12")
else ()
    find_program (LLVM_RANLIB_PATH NAMES "llvm-ranlib-${COMPILER_VERSION_MAJOR}" "llvm-ranlib")
endif ()

if (LLVM_RANLIB_PATH)
    set (CMAKE_RANLIB "${LLVM_RANLIB_PATH}")
endif ()

message(STATUS "Using ranlib: ${CMAKE_RANLIB}")

# Install Name Tool

if (COMPILER_GCC)
    find_program (LLVM_INSTALL_NAME_TOOL_PATH NAMES "llvm-install-name-tool" "llvm-install-name-tool-15" "llvm-install-name-tool-14" "llvm-install-name-tool-13" "llvm-install-name-tool-12")
else ()
    find_program (LLVM_INSTALL_NAME_TOOL_PATH NAMES "llvm-install-name-tool-${COMPILER_VERSION_MAJOR}" "llvm-install-name-tool")
endif ()

if (LLVM_INSTALL_NAME_TOOL_PATH)
    set (CMAKE_INSTALL_NAME_TOOL "${LLVM_INSTALL_NAME_TOOL_PATH}")
endif ()

message(STATUS "Using install-name-tool: ${CMAKE_INSTALL_NAME_TOOL}")

# Objcopy

if (COMPILER_GCC)
    find_program (OBJCOPY_PATH NAMES "llvm-objcopy" "llvm-objcopy-15" "llvm-objcopy-14" "llvm-objcopy-13" "llvm-objcopy-12" "objcopy")
else ()
    find_program (OBJCOPY_PATH NAMES "llvm-objcopy-${COMPILER_VERSION_MAJOR}" "llvm-objcopy" "objcopy")
endif ()

if (OBJCOPY_PATH)
    message (STATUS "Using objcopy: ${OBJCOPY_PATH}")
else ()
    message (FATAL_ERROR "Cannot find objcopy.")
endif ()

# Strip

if (COMPILER_GCC)
    find_program (STRIP_PATH NAMES "llvm-strip" "llvm-strip-15" "llvm-strip-14" "llvm-strip-13" "llvm-strip-12" "strip")
else ()
    find_program (STRIP_PATH NAMES "llvm-strip-${COMPILER_VERSION_MAJOR}" "llvm-strip" "strip")
endif ()

if (STRIP_PATH)
    message (STATUS "Using strip: ${STRIP_PATH}")
else ()
    message (FATAL_ERROR "Cannot find strip.")
endif ()

if (OS_DARWIN AND NOT CMAKE_TOOLCHAIN_FILE)
    # utils/list-licenses/list-licenses.sh (which generates system table system.licenses) needs the GNU versions of find and grep. These are
    # not available out-of-the-box on Mac. As a special case, Darwin builds in CI are cross-compiled from x86 Linux where the GNU userland is
    # available.
    find_program(GFIND_PATH NAMES "gfind")
    if (NOT GFIND_PATH)
        message (FATAL_ERROR "GNU find not found. You can install it with 'brew install findutils'.")
    endif()
    find_program(GGREP_PATH NAMES "ggrep")
    if (NOT GGREP_PATH)
        message (FATAL_ERROR "GNU grep not found. You can install it with 'brew install grep'.")
    endif()
endif ()
