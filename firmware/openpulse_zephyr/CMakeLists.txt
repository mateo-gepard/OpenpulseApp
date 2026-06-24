cmake_minimum_required(VERSION 3.20.0)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(openpulse_zephyr)

set(OPENPULSE_DEVICE_NAME "OpenPulse" CACHE STRING "BLE advertising/device name")

target_sources(app PRIVATE src/main.c)
target_compile_definitions(app PRIVATE OPENPULSE_DEVICE_NAME="${OPENPULSE_DEVICE_NAME}")
