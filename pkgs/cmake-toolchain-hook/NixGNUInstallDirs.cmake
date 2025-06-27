# NixGNUInstallDirs.cmake
# Unifies CMake's GNUInstallDirs with Nix's multi-output system
# Automatically routes files to correct Nix outputs ($outputDev, $outputBin, etc.)
# Include standard GNUInstallDirs first
include(GNUInstallDirs)

function(_nix_get_output_path output_var_name fallback_output)
    # Get the Nix output path with fallback logic
    if(DEFINED ENV{${output_var_name}} AND NOT "$ENV{${output_var_name}}" STREQUAL "")
        set(output_path "$ENV{${output_var_name}}")
    elseif(DEFINED ENV{${fallback_output}} AND NOT "$ENV{${fallback_output}}" STREQUAL "")
        set(output_path "$ENV{${fallback_output}}")
    else()
        # Final fallback to current output
        set(output_path "$ENV{out}")
    endif()
    
    set(${output_var_name}_PATH "${output_path}" PARENT_SCOPE)
    message(DEBUG "Nix output ${output_var_name} -> ${output_path}")
endfunction()

function(_nix_override_install_dir cmake_var nix_output_path subdir)
    # Override a CMAKE_INSTALL_* variable to point to Nix output
    if(nix_output_path AND NOT "${nix_output_path}" STREQUAL "")
        if(subdir)
            set(full_path "${nix_output_path}/${subdir}")
        else()
            set(full_path "${nix_output_path}")
        endif()
        
        set(${cmake_var} "${full_path}" CACHE PATH "Nix-managed ${cmake_var}" FORCE)
        message(DEBUG "Override ${cmake_var} = ${full_path}")
    endif()
endfunction()

# Only activate Nix integration if we're in a Nix build environment
if(DEFINED ENV{NIX_BUILD_TOP} OR DEFINED ENV{out})
    message(STATUS "Detected Nix build environment - integrating with Nix outputs")
    
    # Get all Nix output paths with fallback logic
    _nix_get_output_path("outputDev" "out")
    _nix_get_output_path("outputBin" "out") 
    _nix_get_output_path("outputLib" "out")
    _nix_get_output_path("outputDoc" "out")
    _nix_get_output_path("outputDevdoc" "outputDoc")
    _nix_get_output_path("outputMan" "outputBin")
    _nix_get_output_path("outputDevman" "outputMan")
    _nix_get_output_path("outputInfo" "outputBin")
    
    # Map GNUInstallDirs to appropriate Nix outputs
    
    # Development files go to $outputDev
    _nix_override_install_dir(CMAKE_INSTALL_INCLUDEDIR "${outputDev_PATH}" "include")
    
    # User binaries go to $outputBin  
    _nix_override_install_dir(CMAKE_INSTALL_BINDIR "${outputBin_PATH}" "bin")
    _nix_override_install_dir(CMAKE_INSTALL_SBINDIR "${outputBin_PATH}" "sbin")
    
    # Libraries go to $outputLib
    _nix_override_install_dir(CMAKE_INSTALL_LIBDIR "${outputLib_PATH}" "lib")
    _nix_override_install_dir(CMAKE_INSTALL_LIBEXECDIR "${outputLib_PATH}" "libexec")
    
    # Documentation goes to $outputDoc
    _nix_override_install_dir(CMAKE_INSTALL_DOCDIR "${outputDoc_PATH}" "share/doc/${PROJECT_NAME}")
    _nix_override_install_dir(CMAKE_INSTALL_DATADIR "${outputDoc_PATH}" "share")
    _nix_override_install_dir(CMAKE_INSTALL_DATAROOTDIR "${outputDoc_PATH}" "share")
    
    # Man pages have special handling
    # Check if we need to split dev man pages (section 3) from user man pages
    if(outputDevman_PATH AND NOT "${outputDevman_PATH}" STREQUAL "${outputMan_PATH}")
        # We have separate outputs for dev and user man pages
        _nix_override_install_dir(CMAKE_INSTALL_MANDIR "${outputMan_PATH}" "share/man")
        # Note: Section 3 man pages would need special handling in install() commands
        # This is a limitation - CMake doesn't have built-in support for splitting man sections
        message(STATUS "Note: Manual handling required for section 3 man pages -> ${outputDevman_PATH}")
    else()
        # All man pages go to the same output
        _nix_override_install_dir(CMAKE_INSTALL_MANDIR "${outputMan_PATH}" "share/man")
    endif()
    
    # Info pages go to $outputInfo
    _nix_override_install_dir(CMAKE_INSTALL_INFODIR "${outputInfo_PATH}" "share/info")
    
    # Handle pkg-config and CMake config files (development)
    # These aren't standard GNUInstallDirs but are commonly used
    if(outputDev_PATH)
        set(CMAKE_INSTALL_PKGCONFIGDIR "${outputDev_PATH}/lib/pkgconfig" CACHE PATH "Pkg-config files")
        set(CMAKE_INSTALL_CMAKEDIR "${outputDev_PATH}/lib/cmake" CACHE PATH "CMake config files")
        
        # Also set common alternative names
        set(CMAKE_INSTALL_LIBDIR_PKGCONFIG "${outputDev_PATH}/lib/pkgconfig" CACHE PATH "Pkg-config files")
        set(CMAKE_INSTALL_LIBDIR_CMAKE "${outputDev_PATH}/lib/cmake" CACHE PATH "CMake config files")
    endif()
    
    # Handle system directories that should stay in main output
    # These typically go to $out since they're not user-specific
    if(DEFINED ENV{out})
        _nix_override_install_dir(CMAKE_INSTALL_SYSCONFDIR "$ENV{out}" "etc")
        _nix_override_install_dir(CMAKE_INSTALL_LOCALSTATEDIR "$ENV{out}" "var") 
        _nix_override_install_dir(CMAKE_INSTALL_RUNSTATEDIR "$ENV{out}" "var/run")
        _nix_override_install_dir(CMAKE_INSTALL_SHAREDSTATEDIR "$ENV{out}" "com")
    endif()
    
    # Locale data usually goes with the main package
    if(outputDoc_PATH)
        _nix_override_install_dir(CMAKE_INSTALL_LOCALEDIR "${outputDoc_PATH}" "share/locale")
    endif()
    
    # Create convenience variables for common patterns
    set(NIX_INSTALL_DEVELOPMENT_FILES "${outputDev_PATH}" CACHE PATH "Base path for development files")
    set(NIX_INSTALL_RUNTIME_FILES "$ENV{out}" CACHE PATH "Base path for runtime files")
    set(NIX_INSTALL_USER_BINARIES "${outputBin_PATH}" CACHE PATH "Base path for user binaries")
    set(NIX_INSTALL_LIBRARIES "${outputLib_PATH}" CACHE PATH "Base path for libraries")
    set(NIX_INSTALL_DOCUMENTATION "${outputDoc_PATH}" CACHE PATH "Base path for documentation")
    
    # Print summary
    message(STATUS "Nix output mapping:")
    message(STATUS "  Development files -> ${outputDev_PATH}")
    message(STATUS "  User binaries     -> ${outputBin_PATH}") 
    message(STATUS "  Libraries         -> ${outputLib_PATH}")
    message(STATUS "  Documentation     -> ${outputDoc_PATH}")
    message(STATUS "  Man pages         -> ${outputMan_PATH}")
    message(STATUS "  Info pages        -> ${outputInfo_PATH}")
    
else()
    message(DEBUG "Not in Nix build environment - using standard GNUInstallDirs")
endif()

# Helper macro for installing development vs runtime files
macro(nix_install_files)
    set(options DEVELOPMENT RUNTIME)
    set(oneValueArgs DESTINATION COMPONENT)
    set(multiValueArgs FILES DIRECTORY TARGETS)
    cmake_parse_arguments(NIF "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    
    if(NIF_DEVELOPMENT AND DEFINED NIX_INSTALL_DEVELOPMENT_FILES)
        set(base_dest "${NIX_INSTALL_DEVELOPMENT_FILES}")
    elseif(NIF_RUNTIME AND DEFINED NIX_INSTALL_RUNTIME_FILES)
        set(base_dest "${NIX_INSTALL_RUNTIME_FILES}")
    else()
        set(base_dest "${CMAKE_INSTALL_PREFIX}")
    endif()
    
    if(NIF_DESTINATION)
        set(full_dest "${base_dest}/${NIF_DESTINATION}")
    else()
        set(full_dest "${base_dest}")
    endif()
    
    # Forward to standard install() command
    if(NIF_FILES)
        install(FILES ${NIF_FILES} DESTINATION "${full_dest}" ${NIF_COMPONENT})
    elseif(NIF_DIRECTORY)
        install(DIRECTORY ${NIF_DIRECTORY} DESTINATION "${full_dest}" ${NIF_COMPONENT})
    elseif(NIF_TARGETS)
        install(TARGETS ${NIF_TARGETS} DESTINATION "${full_dest}" ${NIF_COMPONENT})
    endif()
endmacro()

# Helper function to install man pages with section-aware output routing
function(nix_install_man_pages)
    set(multiValueArgs FILES)
    cmake_parse_arguments(NIMP "" "" "${multiValueArgs}" ${ARGN})
    
    foreach(man_file IN LISTS NIMP_FILES)
        # Extract section from filename (e.g., foo.3 -> section 3)
        get_filename_component(man_name "${man_file}" NAME)
        if(man_name MATCHES "\\.([0-9])(\\.gz)?$")
            set(section "${CMAKE_MATCH_1}")
            
            # Section 3 is developer documentation, others are user documentation
            if("${section}" STREQUAL "3" AND outputDevman_PATH AND NOT "${outputDevman_PATH}" STREQUAL "${outputMan_PATH}")
                install(FILES "${man_file}" DESTINATION "${outputDevman_PATH}/share/man/man${section}")
            else()
                install(FILES "${man_file}" DESTINATION "${CMAKE_INSTALL_MANDIR}/man${section}")
            endif()
        else()
            # Can't determine section, use default location
            install(FILES "${man_file}" DESTINATION "${CMAKE_INSTALL_MANDIR}")
        endif()
    endforeach()
endfunction()
