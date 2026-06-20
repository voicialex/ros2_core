# toolchain/aarch64-tryrun-results.cmake
# Pre-filled TRY_RUN results for aarch64 cross-compilation.
# These cannot be auto-detected because target binaries can't run on the host.

# Fast-DDS: shared_mutex priority check (PTHREAD_RWLOCK_PREFER_READER_NP on Linux)
set(SM_RUN_RESULT "0" CACHE STRING "Result from TRY_RUN" FORCE)
set(SM_RUN_RESULT__TRYRUN_OUTPUT "PTHREAD_RWLOCK_PREFER_READER_NP" CACHE STRING "Output from TRY_RUN" FORCE)
set(SM_RUN_OUTPUT "PTHREAD_RWLOCK_PREFER_READER_NP" CACHE STRING "Output from TRY_RUN" FORCE)
