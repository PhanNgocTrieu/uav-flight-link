cmake_minimum_required(VERSION 3.20)
project(uav_flight_link CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)  # để clang-tidy dùng được

# Cảnh báo nghiêm ngặt — chuẩn senior C++ project
add_compile_options(-Wall -Wextra -Wpedantic -Werror)

option(BUILD_TESTS "Build unit tests" ON)

# --- Dependency: GoogleTest qua FetchContent ---
include(FetchContent)
FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG v1.15.2
)
# Không override compiler/linker flags của project cha
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

enable_testing()

# --- Subdirectories: libs sẽ được thêm dần qua từng Phase ---
# add_subdirectory(libs/hal)         # Phase 2
# add_subdirectory(libs/rtos_util)   # Phase 3
# add_subdirectory(libs/protocol)    # Phase 4
# add_subdirectory(libs/ipc)         # Phase 5
# add_subdirectory(libs/security)    # Phase 6

# --- Apps: sẽ được thêm dần ---
# add_subdirectory(apps/flight_controller)
# add_subdirectory(apps/datalink_gateway)

if(BUILD_TESTS)
    add_subdirectory(tests)
endif()
