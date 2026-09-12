cmake_minimum_required(VERSION 3.19)
project(upic LANGUAGES NONE)

set(PDCMAKE_FILE "${CMAKE_BINARY_DIR}/pd.cmake")

if(NOT EXISTS "${PDCMAKE_FILE}")
    file(DOWNLOAD "https://raw.githubusercontent.com/pure-data/pd.cmake/refs/heads/main/pd.cmake" "${PDCMAKE_FILE}"
         STATUS DOWNLOAD_STATUS)

    list(
        GET
        DOWNLOAD_STATUS
        0
        DOWNLOAD_CODE)
    list(
        GET
        DOWNLOAD_STATUS
        1
        DOWNLOAD_MESSAGE)

    if(NOT
       DOWNLOAD_CODE
       EQUAL
       0)
        message(FATAL_ERROR "Could not download pd.cmake: ${DOWNLOAD_MESSAGE}")
    endif()
endif()

include("${PDCMAKE_FILE}")

# ALL makes this part of the default build.
add_custom_target(upic ALL)

pd_add_datafile(upic "${CMAKE_CURRENT_SOURCE_DIR}/src/")

file(
    GLOB
    UPIC_RESOURCE_FILES
    CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/resources/*")

if(UPIC_RESOURCE_FILES)
    pd_add_datafile(upic "${UPIC_RESOURCE_FILES}")
endif()
