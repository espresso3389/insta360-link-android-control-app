cmake_minimum_required(VERSION 3.22.1)

project(native_tracker)

set(PROJECT_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../)
set(THIRD_PARTY_ROOT ${PROJECT_ROOT}/third_party)
set(LIBUSB_ROOT ${THIRD_PARTY_ROOT}/libusb)
set(LIBUVC_ROOT ${THIRD_PARTY_ROOT}/libuvc)

add_library(
    libusb_static
    STATIC
    ${LIBUSB_ROOT}/libusb/core.c
    ${LIBUSB_ROOT}/libusb/descriptor.c
    ${LIBUSB_ROOT}/libusb/hotplug.c
    ${LIBUSB_ROOT}/libusb/io.c
    ${LIBUSB_ROOT}/libusb/sync.c
    ${LIBUSB_ROOT}/libusb/strerror.c
    ${LIBUSB_ROOT}/libusb/os/linux_usbfs.c
    ${LIBUSB_ROOT}/libusb/os/events_posix.c
    ${LIBUSB_ROOT}/libusb/os/threads_posix.c
    ${LIBUSB_ROOT}/libusb/os/linux_netlink.c
)

target_include_directories(
    libusb_static
    PUBLIC
    ${LIBUSB_ROOT}/libusb
    PRIVATE
    ${LIBUSB_ROOT}/android
    ${LIBUSB_ROOT}/libusb/os
)

set(libuvc_VERSION_MAJOR 0)
set(libuvc_VERSION_MINOR 0)
set(libuvc_VERSION_PATCH 7)
set(libuvc_VERSION 0.0.7)
configure_file(
    ${LIBUVC_ROOT}/include/libuvc/libuvc_config.h.in
    ${CMAKE_CURRENT_BINARY_DIR}/generated/libuvc/libuvc_config.h
    @ONLY
)

add_library(
    libuvc_static
    STATIC
    ${LIBUVC_ROOT}/src/ctrl.c
    ${LIBUVC_ROOT}/src/ctrl-gen.c
    ${LIBUVC_ROOT}/src/device.c
    ${LIBUVC_ROOT}/src/diag.c
    ${LIBUVC_ROOT}/src/frame.c
    ${LIBUVC_ROOT}/src/init.c
    ${LIBUVC_ROOT}/src/stream.c
    ${LIBUVC_ROOT}/src/misc.c
)

target_include_directories(
    libuvc_static
    PUBLIC
    ${LIBUVC_ROOT}/include
    ${CMAKE_CURRENT_BINARY_DIR}/generated
    PRIVATE
    ${LIBUSB_ROOT}/libusb
)

add_library(
    native_tracker
    SHARED
    native_tracker.cpp
)

find_library(log-lib log)

target_link_libraries(
    libusb_static
    ${log-lib}
)

target_link_libraries(
    libuvc_static
    libusb_static
    ${log-lib}
)

target_link_libraries(
    native_tracker
    libuvc_static
    libusb_static
    ${log-lib}
)
