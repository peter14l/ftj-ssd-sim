cmake_minimum_required(VERSION 3.15)
project(FTJMemorySim LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Configure header include directories
include_directories(include)
# WinFsp SDK paths are Windows-specific; only add on Windows
if (WIN32)
    include_directories("C:/Program Files (x86)/WinFsp/inc")
endif()

# Define the core simulator library
add_library(ftj_engine
    src/ftj_engine.cpp
    include/ftj_engine.hpp
)

# Target compile options for MSVC and Clang/GCC on Windows
if(MSVC)
    target_compile_options(ftj_engine PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(ftj_engine PRIVATE -Wall -Wextra -Werror)
endif()

# Define the CLI benchmark executable
add_executable(ftj_sim_cli src/main.cpp)
target_link_libraries(ftj_sim_cli PRIVATE ftj_engine)

if(MSVC)
    target_compile_options(ftj_sim_cli PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(ftj_sim_cli PRIVATE -Wall -Wextra -Werror)
endif()

# Define a small tests executable
add_executable(ftj_tests src/tests.cpp)
target_link_libraries(ftj_tests PRIVATE ftj_engine)
if(MSVC)
    target_compile_options(ftj_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(ftj_tests PRIVATE -Wall -Wextra -Werror)
endif()

# WAF/Endurance harness
add_executable(ftj_waf_harness src/waf_harness.cpp)
target_link_libraries(ftj_waf_harness PRIVATE ftj_engine)
if(MSVC)
    target_compile_options(ftj_waf_harness PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(ftj_waf_harness PRIVATE -Wall -Wextra -Werror)
endif()

# Define the Virtual Disk Server executable (Windows-only)
if (WIN32)
    add_executable(ftj_vdisk_srv
        src/win_vdisk.cpp
        src/win_vdisk_srv.c
    )
    target_link_libraries(ftj_vdisk_srv PRIVATE ftj_engine "C:/Program Files (x86)/WinFsp/lib/winfsp-x64.lib")

    if(MSVC)
        # Use relaxed permissive mode for official SDK code compatibility
        target_compile_options(ftj_vdisk_srv PRIVATE /W4 /permissive /Zc:strictStrings- /utf-8)
    else()
        target_compile_options(ftj_vdisk_srv PRIVATE -Wall -Wextra -Werror)
    endif()

    add_custom_command(TARGET ftj_vdisk_srv POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "C:/Program Files (x86)/WinFsp/bin/winfsp-x64.dll"
        $<TARGET_FILE_DIR:ftj_vdisk_srv>
    )
endif()

