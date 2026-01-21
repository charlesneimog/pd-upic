cmake_minimum_required(VERSION 3.15)
project(upic)

set(PDCMAKE_FILE ${CMAKE_BINARY_DIR}/pd.cmake)
set(PDCMAKE_VERSION "v0.2.11")
if(NOT EXISTS "${PDCMAKE_FILE}")
    file(DOWNLOAD https://raw.githubusercontent.com/pure-data/pd.cmake/refs/tags/${PDCMAKE_VERSION}/pd.cmake ${PDCMAKE_FILE})
endif()
include(${PDCMAKE_FILE})

add_custom_target(upic COMMAND echo "Installing dependencies from upic...")
pd_add_datafile(upic "${CMAKE_CURRENT_SOURCE_DIR}/src/")

file(GLOB UPIC_RESOURCES_FILES "${CMAKE_CURRENT_SOURCE_DIR}/resources/*")
pd_add_datafile(upic "${UPIC_RESOURCES_FILES}")
