cmake_policy(PUSH)
cmake_minimum_required(VERSION 3.24)

# Track if the provider was actually used
set_property(GLOBAL PROPERTY NIX_PROVIDER_TRIGGERED FALSE)

# Promote targets of a package to GLOBAL scope
function(nix_promote_package_targets package)
    get_property(targets GLOBAL PROPERTY ${package}_TARGETS)
    if(NOT targets)
        # Try to find targets using common naming patterns if not already tracked
        # This is a fallback - most modern packages should be handled by find_package
        return()
    endif()

    foreach(target IN LISTS targets)
        if(TARGET ${target})
            get_target_property(is_imported ${target} IMPORTED)
            if(is_imported)
                set_target_properties(${target} PROPERTIES IMPORTED_GLOBAL TRUE)
            endif()
        endif()
    endforeach()
endfunction()

function(nix_debug_find_library lib_name)
    message(STATUS "=== Debugging find_library for ${lib_name} ===")
    get_property(lib_suffixes GLOBAL PROPERTY CMAKE_FIND_LIBRARY_SUFFIXES)
    message(STATUS "Library suffixes: ${lib_suffixes}")
    
    foreach(path IN LISTS CMAKE_SYSTEM_LIBRARY_PATH)
        message(STATUS "Checking library path: ${path}")
        if(EXISTS "${path}")
            file(GLOB lib_files "${path}/lib${lib_name}.*")
            if(lib_files)
                message(STATUS "  Found libraries: ${lib_files}")
            else()
                message(STATUS "  No libraries matching lib${lib_name}.* found")
            endif()
        else()
            message(STATUS "  Path does not exist")
        endif()
    endforeach()
    message(STATUS "=== End debug for ${lib_name} ===")
endfunction()

function(process_nix_dependency dep_path host_offset target_offset current_host_offset current_target_offset)
    message(DEBUG "Processing dependency: ${dep_path}")
    message(DEBUG "  Dependency offsets: host=${host_offset}, target=${target_offset}")
    message(DEBUG "  Current platform offsets: host=${current_host_offset}, target=${current_target_offset}")
    
    math(EXPR effective_host_offset "${host_offset} - ${current_host_offset}")
    math(EXPR effective_target_offset "${target_offset} - ${current_target_offset}")
    
    message(DEBUG "  Effective offsets: host=${effective_host_offset}, target=${effective_target_offset}")
    
    list(APPEND CMAKE_SYSTEM_PREFIX_PATH "${dep_path}")
    
    if(${effective_host_offset} EQUAL 0 AND ${effective_target_offset} EQUAL 0)
        # Host -> Host: Runtime dependencies for the host platform
        message(DEBUG "  Type: Host->Host (runtime)")
    elseif(${effective_host_offset} EQUAL -1 AND ${effective_target_offset} EQUAL 0)
        # Build -> Host: Native build tools
        message(DEBUG "  Type: Build->Host (native tools)")
        if(EXISTS "${dep_path}/bin")
            list(APPEND CMAKE_SYSTEM_PROGRAM_PATH "${dep_path}/bin")
        endif()
        
    elseif(${effective_host_offset} EQUAL 0 AND ${effective_target_offset} EQUAL 1)
        # Host -> Target: Libraries to link into target
        message(DEBUG "  Type: Host->Target (target libraries)")
        if(EXISTS "${dep_path}/include")
            list(APPEND CMAKE_SYSTEM_INCLUDE_PATH "${dep_path}/include")
        endif()
        if(EXISTS "${dep_path}/lib")
            list(APPEND CMAKE_SYSTEM_LIBRARY_PATH "${dep_path}/lib")
        endif()
        if(EXISTS "${dep_path}/Library/Frameworks")
            list(APPEND CMAKE_SYSTEM_FRAMEWORK_PATH "${dep_path}/Library/Frameworks")
        endif()
        if(EXISTS "${dep_path}/Applications")
            list(APPEND CMAKE_SYSTEM_APPBUNDLE_PATH "${dep_path}/Applications")
        endif()
        
    elseif(${effective_host_offset} EQUAL -1 AND ${effective_target_offset} EQUAL -1)
        # Build -> Build: Build-time tools for building other build tools
        message(DEBUG "  Type: Build->Build (build tools)")
        if(EXISTS "${dep_path}/bin")
            list(APPEND CMAKE_SYSTEM_PROGRAM_PATH "${dep_path}/bin")
        endif()
        
    elseif(${effective_host_offset} EQUAL -1 AND ${effective_target_offset} EQUAL 1)
        # Build -> Target: Tools that produce target artifacts
        message(DEBUG "  Type: Build->Target (cross tools)")
        if(EXISTS "${dep_path}/bin")
            list(APPEND CMAKE_SYSTEM_PROGRAM_PATH "${dep_path}/bin")
        endif()
        
    elseif(${effective_host_offset} EQUAL 1 AND ${effective_target_offset} EQUAL 1)
        message(DEBUG "  Type: Target->Target (target runtime)")
        if(EXISTS "${dep_path}/lib")
            # Add to rpath but not to link-time search paths
            list(APPEND CMAKE_BUILD_RPATH "${dep_path}/lib") 
            list(APPEND CMAKE_INSTALL_RPATH "${dep_path}/lib")
        endif()
    else()
        message(DEBUG "  Type: Unknown offset combination")
    endif()
    
    # Handle multi-output packages
    string(REGEX MATCH "^(.+)-([^-]+)$" output_match "${dep_path}")
    if(output_match)
        set(base_path "${CMAKE_MATCH_1}")
        set(current_output "${CMAKE_MATCH_2}")
        
        message(DEBUG "  Multi-output detected: base=${base_path}, current=${current_output}")
        
        set(nix_outputs "dev" "lib" "bin" "out" "static" "doc" "man" "info")
        
        foreach(output IN LISTS nix_outputs)
            if(NOT "${output}" STREQUAL "${current_output}")
                set(output_path "${base_path}-${output}")
                
                if(EXISTS "${output_path}")
                    message(DEBUG "  Found additional output: ${output_path}")
                    
                    list(APPEND CMAKE_SYSTEM_PREFIX_PATH "${output_path}")
                    
                    # Apply same logic to additional outputs
                    if(${effective_host_offset} EQUAL 0 AND ${effective_target_offset} EQUAL 1)
                        # Target libraries/headers
                        if("${output}" STREQUAL "dev" AND EXISTS "${output_path}/include")
                            list(APPEND CMAKE_SYSTEM_INCLUDE_PATH "${output_path}/include")
                        endif()
                        if(("${output}" STREQUAL "lib" OR "${output}" STREQUAL "out") AND EXISTS "${output_path}/lib")
                            list(APPEND CMAKE_SYSTEM_LIBRARY_PATH "${output_path}/lib")
                        endif()
                    elseif((${effective_host_offset} EQUAL -1 AND ${effective_target_offset} EQUAL 0) OR 
                           (${effective_host_offset} EQUAL -1 AND ${effective_target_offset} EQUAL -1) OR
                           (${effective_host_offset} EQUAL -1 AND ${effective_target_offset} EQUAL 1))
                        # Native tools
                        if(("${output}" STREQUAL "bin" OR "${output}" STREQUAL "out") AND EXISTS "${output_path}/bin")
                            list(APPEND CMAKE_SYSTEM_PROGRAM_PATH "${output_path}/bin")
                        endif()
                    endif()
                    
                    # CMake config files can be in any output
                    if(EXISTS "${output_path}/lib/cmake")
                        list(APPEND CMAKE_SYSTEM_PREFIX_PATH "${output_path}")
                    endif()
                    if(EXISTS "${output_path}/share/cmake")
                        list(APPEND CMAKE_SYSTEM_PREFIX_PATH "${output_path}")
                    endif()
                endif()
            endif()
        endforeach()
    endif()
    
    # Propagate changes to parent scope
    set(CMAKE_SYSTEM_PREFIX_PATH "${CMAKE_SYSTEM_PREFIX_PATH}" PARENT_SCOPE)
    set(CMAKE_SYSTEM_INCLUDE_PATH "${CMAKE_SYSTEM_INCLUDE_PATH}" PARENT_SCOPE)
    set(CMAKE_SYSTEM_LIBRARY_PATH "${CMAKE_SYSTEM_LIBRARY_PATH}" PARENT_SCOPE)
    set(CMAKE_SYSTEM_PROGRAM_PATH "${CMAKE_SYSTEM_PROGRAM_PATH}" PARENT_SCOPE)
    set(CMAKE_SYSTEM_FRAMEWORK_PATH "${CMAKE_SYSTEM_FRAMEWORK_PATH}" PARENT_SCOPE)
    set(CMAKE_SYSTEM_APPBUNDLE_PATH "${CMAKE_SYSTEM_APPBUNDLE_PATH}" PARENT_SCOPE)
endfunction()

function(process_nix_dependencies hostOffset targetOffset)
    message(STATUS "Processing Nix dependencies with offsets: host=${hostOffset}, target=${targetOffset}")
    
    set(dep_info_list
        "depsBuildBuild" "-1" "-1"
        "nativeBuildInputs" "-1" "0"
        "depsBuildTarget" "-1" "1"
        "depsHostHost" "0" "0"
        "buildInputs" "0" "1"
        "depsTargetTarget" "1" "1"
        "depsBuildBuildPropagated" "-1" "-1"
        "propagatedNativeBuildInputs" "-1" "0"
        "depsBuildTargetPropagated" "-1" "1"
        "depsHostHostPropagated" "0" "0"
        "propagatedBuildInputs" "0" "1"
        "depsTargetTargetPropagated" "1" "1"
    )
    
    list(LENGTH dep_info_list list_length)
    math(EXPR num_deps "${list_length} / 3")
    
    set(i 0)
    while(i LESS num_deps)
        math(EXPR var_index "${i} * 3")
        math(EXPR host_index "${i} * 3 + 1")
        math(EXPR target_index "${i} * 3 + 2")
        
        list(GET dep_info_list ${var_index} var_name)
        list(GET dep_info_list ${host_index} dep_host_offset)
        list(GET dep_info_list ${target_index} dep_target_offset)
        
        if(DEFINED ENV{${var_name}})
            message(DEBUG "Processing ${var_name} (${dep_host_offset}, ${dep_target_offset})")
            string(REPLACE " " ";" deps "$ENV{${var_name}}")
            foreach(dep_path IN LISTS deps)
                if(EXISTS "${dep_path}")
                    process_nix_dependency("${dep_path}" "${dep_host_offset}" "${dep_target_offset}" "${hostOffset}" "${targetOffset}")
                endif()
            endforeach()
        endif()
        
        math(EXPR i "${i} + 1")
    endwhile()
    
    list(REMOVE_DUPLICATES CMAKE_SYSTEM_PREFIX_PATH)
    list(REMOVE_DUPLICATES CMAKE_SYSTEM_INCLUDE_PATH)
    list(REMOVE_DUPLICATES CMAKE_SYSTEM_LIBRARY_PATH)
    list(REMOVE_DUPLICATES CMAKE_SYSTEM_PROGRAM_PATH)
    if(CMAKE_SYSTEM_FRAMEWORK_PATH)
        list(REMOVE_DUPLICATES CMAKE_SYSTEM_FRAMEWORK_PATH)
    endif()
    if(CMAKE_SYSTEM_APPBUNDLE_PATH)
        list(REMOVE_DUPLICATES CMAKE_SYSTEM_APPBUNDLE_PATH)
    endif()
    
    set(CMAKE_SYSTEM_PREFIX_PATH "${CMAKE_SYSTEM_PREFIX_PATH}" CACHE INTERNAL "System prefix paths from Nix")
    set(CMAKE_SYSTEM_INCLUDE_PATH "${CMAKE_SYSTEM_INCLUDE_PATH}" CACHE INTERNAL "System include paths from Nix")
    set(CMAKE_SYSTEM_LIBRARY_PATH "${CMAKE_SYSTEM_LIBRARY_PATH}" CACHE INTERNAL "System library paths from Nix")
    set(CMAKE_SYSTEM_PROGRAM_PATH "${CMAKE_SYSTEM_PROGRAM_PATH}" CACHE INTERNAL "System program paths from Nix")
    set(CMAKE_SYSTEM_FRAMEWORK_PATH "${CMAKE_SYSTEM_FRAMEWORK_PATH}" CACHE INTERNAL "System framework paths from Nix")
    set(CMAKE_SYSTEM_APPBUNDLE_PATH "${CMAKE_SYSTEM_APPBUNDLE_PATH}" CACHE INTERNAL "System app bundle paths from Nix")
    
    message(STATUS "Nix dependencies processed successfully")
endfunction()

# For native builds: process_nix_dependencies(0 0)
if(NOT DEFINED NIX_HOST_OFFSET)
    set(NIX_HOST_OFFSET 0)
endif()
if(NOT DEFINED NIX_TARGET_OFFSET)
    set(NIX_TARGET_OFFSET 0)
endif()

process_nix_dependencies("${NIX_HOST_OFFSET}" "${NIX_TARGET_OFFSET}")

message(STATUS "====== LOADED cmakeBuildHook.cmake ======")

# ============================================================================
# Nix CMake Dependency Provider
# ============================================================================
if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.24")
    # CPM support: Set source cache if provided by Nix
    if(DEFINED ENV{NIX_CPM_SOURCE_CACHE})
        set(CPM_SOURCE_CACHE "$ENV{NIX_CPM_SOURCE_CACHE}" CACHE PATH "Nix-managed CPM cache")
        set(ENV{CPM_SOURCE_CACHE} "$ENV{NIX_CPM_SOURCE_CACHE}")
    endif()

    message(STATUS "Setting up Nix dependency provider for FetchContent interception")

    include(FetchContent)

    macro(nix_dependency_provider method)
        # Check both environment and CMake variables for discovery mode
        if(DEFINED NIX_CMAKE_DISCOVERY_MODE OR DEFINED ENV{NIX_CMAKE_DISCOVERY_MODE})
            set(_discovery_mode TRUE)
        else()
            set(_discovery_mode FALSE)
        endif()

        if(DEFINED NIX_CMAKE_DISCOVERY_LOG)
            set(_discovery_log "${NIX_CMAKE_DISCOVERY_LOG}")
        elseif(DEFINED ENV{NIX_CMAKE_DISCOVERY_LOG})
            set(_discovery_log "$ENV{NIX_CMAKE_DISCOVERY_LOG}")
        endif()

        if(DEFINED NIX_CMAKE_RECURSIVE_DISCOVERY OR DEFINED ENV{NIX_CMAKE_RECURSIVE_DISCOVERY})
            set(_recursive_discovery TRUE)
        else()
            set(_recursive_discovery FALSE)
        endif()

        set_property(GLOBAL PROPERTY NIX_PROVIDER_TRIGGERED TRUE)
        if("${method}" STREQUAL "FETCHCONTENT_MAKEAVAILABLE_SERIAL")
            set(_args "${ARGN}")
            list(GET _args 0 dep_name)
            message(STATUS "Nix: Intercepting FetchContent_MakeAvailable(${dep_name})")

            # If in discovery mode, log the dependency for lock file generation
            if(_discovery_mode)
                get_property(_already_logged GLOBAL PROPERTY NIX_DISCOVERY_LOGGED_${dep_name})
                if(NOT _already_logged)
                    message(STATUS "Nix: Discovery mode active, logging ${dep_name}")

                    set(_git_repo "")
                    set(_git_tag "")
                    set(_url "")
                    set(_source_dir "")

                    list(LENGTH _args _args_len)
                    set(_idx 0)
                    while(_idx LESS _args_len)
                        list(GET _args ${_idx} _key)
                        math(EXPR _idx_next "${_idx} + 1")
                        if(_idx_next LESS _args_len)
                            list(GET _args ${_idx_next} _value)
                            if(_key STREQUAL "GIT_REPOSITORY")
                                set(_git_repo "${_value}")
                            elseif(_key STREQUAL "GIT_TAG")
                                set(_git_tag "${_value}")
                            elseif(_key STREQUAL "URL")
                                set(_url "${_value}")
                            elseif(_key STREQUAL "SOURCE_DIR")
                                set(_source_dir "${_value}")
                            endif()
                        endif()
                        math(EXPR _idx "${_idx} + 1")
                    endwhile()

                    string(JSON dep_json SET "{}" "name" "\"${dep_name}\"")
                    if(_git_repo)
                        string(JSON dep_json SET "${dep_json}" "gitRepository" "\"${_git_repo}\"")
                    endif()
                    if(_git_tag)
                        string(JSON dep_json SET "${dep_json}" "gitTag" "\"${_git_tag}\"")
                    endif()
                    if(_url)
                        string(JSON dep_json SET "${dep_json}" "url" "\"${_url}\"")
                    endif()
                    if(_source_dir)
                        string(JSON dep_json SET "${dep_json}" "sourceDir" "\"${_source_dir}\"")
                    endif()

                    if(_discovery_log)
                        string(REPLACE "\n" " " dep_json_min "${dep_json}")
                        file(APPEND "${_discovery_log}" "${dep_json_min}\n")
                        message(STATUS "Nix: Logged dependency ${dep_name}")
                    endif()

                    set_property(GLOBAL PROPERTY NIX_DISCOVERY_LOGGED_${dep_name} TRUE)
                endif()

                if(_recursive_discovery)
                    message(STATUS "Nix: Recursive discovery active, allowing FetchContent to proceed for ${dep_name}")
                else()
                    # Normal discovery mode: Stub the dependency
                    FetchContent_SetPopulated(${dep_name}
                        SOURCE_DIR "/nix-cmake-discovery-stub"
                        BINARY_DIR "/nix-cmake-discovery-stub"
                    )
                    set(${dep_name}_POPULATED TRUE)

                    string(TOLOWER "${dep_name}" _dep_name_lower)
                    set(${_dep_name_lower}_SOURCE_DIR "/nix-cmake-discovery-stub")
                    set(${_dep_name_lower}_BINARY_DIR "/nix-cmake-discovery-stub")

                    if(NOT TARGET ${dep_name}::${dep_name})
                        add_library(${dep_name}::${dep_name} INTERFACE IMPORTED GLOBAL)
                    endif()
                    if(NOT TARGET ${dep_name})
                        add_library(${dep_name} INTERFACE IMPORTED GLOBAL)
                    endif()

                    # Some packages (like Catch2) have additional sub-targets
                    set(_common_suffixes "WithMain" "Main" "Static" "Shared" "Core" "All")
                    foreach(_suffix IN LISTS _common_suffixes)
                        if(NOT TARGET ${dep_name}::${dep_name}${_suffix})
                            add_library(${dep_name}::${dep_name}${_suffix} INTERFACE IMPORTED GLOBAL)
                        endif()
                    endforeach()

                    return()
                endif()
            endif()

            # Normal build mode logic
            find_package(${dep_name} BYPASS_PROVIDER QUIET GLOBAL)

            # Check if the package was found AND provides the expected targets
            set(_has_targets FALSE)
            if(${dep_name}_FOUND)
                if(TARGET ${dep_name}::${dep_name} OR TARGET ${dep_name})
                    set(_has_targets TRUE)
                endif()
            endif()

            if(${dep_name}_FOUND AND _has_targets)
                message(STATUS "Nix: Using pre-built CMake package for ${dep_name}")
                set(_source_dir "")
                set(_binary_dir "")
                if(DEFINED ${dep_name}_DIR)
                    get_filename_component(_source_dir "${${dep_name}_DIR}/../../../" ABSOLUTE)
                    set(_binary_dir "${_source_dir}")
                else()
                    set(_source_dir "/nix/store/nix-cmake-provider-stub/${dep_name}")
                    set(_binary_dir "${CMAKE_BINARY_DIR}/_deps/${_dep_name_lower}-build")
                endif()

                if(TARGET ${dep_name}::${dep_name})
                    set_target_properties(${dep_name}::${dep_name} PROPERTIES IMPORTED_GLOBAL TRUE)
                endif()
                if(TARGET ${dep_name})
                    set_target_properties(${dep_name} PROPERTIES IMPORTED_GLOBAL TRUE)
                endif()

                FetchContent_SetPopulated(${dep_name} SOURCE_DIR "${_source_dir}" BINARY_DIR "${_binary_dir}")
                string(TOLOWER "${dep_name}" _dep_name_lower)
                set(${_dep_name_lower}_SOURCE_DIR "${_source_dir}" PARENT_SCOPE)
                set(${_dep_name_lower}_BINARY_DIR "${_binary_dir}" PARENT_SCOPE)
            else()
                if(${dep_name}_FOUND AND NOT _has_targets)
                    message(STATUS "Nix: Found package ${dep_name} but it doesn't provide expected targets, falling back to FetchContent")
                else()
                    message(STATUS "Nix: No pre-built package found for ${dep_name}, falling back to FetchContent")
                endif()

                # Check if we have a pre-fetched source from Nix via environment variable
                string(TOUPPER "${dep_name}" _dep_name_upper)
                set(_env_var_name "FETCHCONTENT_SOURCE_DIR_${_dep_name_upper}")
                if(DEFINED ENV{${_env_var_name}})
                    set(_nix_source_dir "$ENV{${_env_var_name}}")
                    message(STATUS "Nix: Using pre-fetched source for ${dep_name} from ${_nix_source_dir}")

                    # Set the FetchContent source directory so CMake uses our pre-fetched source
                    set(FETCHCONTENT_SOURCE_DIR_${_dep_name_upper} "${_nix_source_dir}" PARENT_SCOPE)

                    # Also set it in the current scope for immediate use
                    set(FETCHCONTENT_SOURCE_DIR_${_dep_name_upper} "${_nix_source_dir}")
                endif()
            endif()

        elseif("${method}" STREQUAL "FIND_PACKAGE")
            set(_args "${ARGN}")
            list(GET _args 0 dep_name)
            set(_find_args "${_args}")
            list(REMOVE_ITEM _find_args "REQUIRED")
            message(STATUS "Nix: Intercepting find_package(${dep_name})")
            find_package(${dep_name} ${_find_args} PATHS ${CMAKE_SYSTEM_PREFIX_PATH} NO_DEFAULT_PATH BYPASS_PROVIDER GLOBAL)
            if(NOT ${dep_name}_FOUND)
                find_package(${dep_name} ${ARGN} BYPASS_PROVIDER GLOBAL)
            endif()
        endif()
    endmacro()

    cmake_language(
        SET_DEPENDENCY_PROVIDER nix_dependency_provider
        SUPPORTED_METHODS FETCHCONTENT_MAKEAVAILABLE_SERIAL FIND_PACKAGE
    )

    function(nix_provider_check)
        get_property(_triggered GLOBAL PROPERTY NIX_PROVIDER_TRIGGERED)
        if(NOT _triggered)
            # Normal warning if not triggered, though in discovery it might be fine if no deps are found
        endif()
    endfunction()
    cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL nix_provider_check)

endif()

cmake_policy(POP)
