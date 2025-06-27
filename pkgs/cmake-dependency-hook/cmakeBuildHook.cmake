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
    message(DEBUG "CMAKE_SYSTEM_PREFIX_PATH: ${CMAKE_SYSTEM_PREFIX_PATH}")
    message(DEBUG "CMAKE_SYSTEM_INCLUDE_PATH: ${CMAKE_SYSTEM_INCLUDE_PATH}")
    message(DEBUG "CMAKE_SYSTEM_LIBRARY_PATH: ${CMAKE_SYSTEM_LIBRARY_PATH}")
    message(DEBUG "CMAKE_SYSTEM_PROGRAM_PATH: ${CMAKE_SYSTEM_PROGRAM_PATH}")
    message(DEBUG "CMAKE_SYSTEM_FRAMEWORK_PATH: ${CMAKE_SYSTEM_FRAMEWORK_PATH}")
    message(DEBUG "CMAKE_SYSTEM_APPBUNDLE_PATH: ${CMAKE_SYSTEM_APPBUNDLE_PATH}")
endfunction()

# For native builds: process_nix_dependencies(0 0)
if(NOT DEFINED NIX_HOST_OFFSET)
    set(NIX_HOST_OFFSET 0)
endif()
if(NOT DEFINED NIX_TARGET_OFFSET)
    set(NIX_TARGET_OFFSET 0)
endif()

process_nix_dependencies("${NIX_HOST_OFFSET}" "${NIX_TARGET_OFFSET}")
