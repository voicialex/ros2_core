# toolchain/aarch64-tryrun-results.cmake
# Pre-filled TRY_RUN results for aarch64 cross-compilation
# These values represent expected behavior on Linux aarch64

# Fast-DDS: shared_mutex priority check (works normally on Linux aarch64)
set(SM_RUN_RESULT "0" CACHE STRING "Result from TRY_RUN" FORCE)
set(SM_RUN_RESULT__TRYRUN_OUTPUT "" CACHE STRING "Output from TRY_RUN" FORCE)
