cmake_minimum_required(VERSION 3.20)
project(hyper_ram LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Compiler optimization flags
if (MSVC)
    add_compile_options(/W4 /O2 /Oi /Ot /fp:fast /permissive-)
else()
    add_compile_options(-Wall -Wextra -O3 -march=native)
endif()

include_directories(include)

# HyperRAM Library
add_library(hyper_ram_core STATIC
    src/bdi_engine.cpp
    src/line_table.cpp
    src/hyper_ram_controller.cpp
)

# CLI & Benchmark Executable
add_executable(hyper_ram_sim
    src/main.cpp
)
target_link_libraries(hyper_ram_sim PRIVATE hyper_ram_core)

# Unit & Stress Test Suite
add_executable(hyper_ram_tests
    src/tests.cpp
)
target_link_libraries(hyper_ram_tests PRIVATE hyper_ram_core)

# Standalone Windows Memory Optimizer Utility (For End-Users)
if (WIN32)
    add_executable(HyperRAM_Optimizer
        src/win_optimizer.cpp
    )
    target_link_libraries(HyperRAM_Optimizer PRIVATE psapi)
endif()
