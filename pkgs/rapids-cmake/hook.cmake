# Nix-CMake: RAPIDS CMake Integration Hook

# Intercept rapids_cpm_init and redirect to our dependency provider
macro(rapids_cpm_init)
    message(STATUS "Nix-CMake: Intercepted rapids_cpm_init")
    # Our core dependency provider already handles CPM if injected via CMAKE_PROJECT_TOP_LEVEL_INCLUDES
endmacro()

# Intercept rapids_fetch_export and ensure it doesn't trigger network access during build
macro(rapids_fetch_export dep_name)
    message(STATUS "Nix-CMake: Intercepted rapids_fetch_export for ${dep_name}")
    # Logic to map RAPIDS exports to Nix inputs will go here
endmacro()

# Inject RAPIDS-specific versioning logic if needed
set(RAPIDS_CMAKE_VERSION "@version@" CACHE STRING "Forced RAPIDS-CMake version via Nix")
