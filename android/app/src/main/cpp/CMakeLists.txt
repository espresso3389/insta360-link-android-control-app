cmake_minimum_required(VERSION 3.22.1)

project(native_tracker)

add_library(
    native_tracker
    SHARED
    native_tracker.cpp
)

find_library(log-lib log)

target_link_libraries(
    native_tracker
    ${log-lib}
)
