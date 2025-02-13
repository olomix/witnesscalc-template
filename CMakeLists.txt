cmake_minimum_required(VERSION 3.28)

include(cmake/platform.cmake)

set(USE_ASM ON CACHE BOOL "Use asm implementation for Fr and Fq")

project(witnesscalc LANGUAGES CXX ASM)

if(NOT DEFINED CIRCUIT_FILE)
    message(FATAL_ERROR "CIRCUIT_FILE is required but not provided!")
endif()
file(REAL_PATH ${CIRCUIT_FILE} CIRCUIT_FILE BASE_DIRECTORY ${CMAKE_BINARY_DIR} EXPAND_TILDE)

get_filename_component(CIRCUIT_FILE_EXT ${CIRCUIT_FILE} LAST_EXT)
if(NOT CIRCUIT_FILE_EXT STREQUAL ".cpp")
    message(FATAL_ERROR "CIRCUIT_FILE should have .cpp extension.")
endif()

if(NOT EXISTS ${CIRCUIT_FILE})
    message(FATAL_ERROR "File does not exist: ${CIRCUIT_FILE}")
endif()
message(STATUS "Circuit .cpp file is set to ${CIRCUIT_FILE}")

function(make_valid_cpp_identifier INPUT_STRING OUTPUT_VARIABLE)
    set(IDENTIFIER "${INPUT_STRING}")

    # Replace invalid characters with _
    string(REGEX REPLACE "[^a-zA-Z0-9_]" "_" IDENTIFIER "${IDENTIFIER}")

    # Ensure it does not start with a digit (prefix with an underscore if needed)
    string(REGEX MATCH "^[0-9]" STARTS_WITH_DIGIT "${IDENTIFIER}")
    if(STARTS_WITH_DIGIT)
        set(IDENTIFIER "_${IDENTIFIER}")
    endif()

    # Return the valid identifier
    set(${OUTPUT_VARIABLE} "${IDENTIFIER}" PARENT_SCOPE)
endfunction()

get_filename_component(CIRCUIT_NAME ${CIRCUIT_FILE} NAME_WLE)
make_valid_cpp_identifier("${CIRCUIT_NAME}" CIRCUIT_NAME)
message(STATUS "Circuit name: ${CIRCUIT_NAME}")
string(TOUPPER "${CIRCUIT_NAME}" CIRCUIT_NAME_UPPER)

# Determine the .dat file path
get_filename_component(CIRCUIT_FILE_NAME ${CIRCUIT_FILE} NAME_WLE)
get_filename_component(CIRCUIT_FILE_DIR ${CIRCUIT_FILE} DIRECTORY)
set(CIRCUIT_DAT "${CIRCUIT_FILE_DIR}/${CIRCUIT_FILE_NAME}.dat")
if(NOT EXISTS ${CIRCUIT_DAT})
    message(FATAL_ERROR "Dat file does not exist: ${CIRCUIT_DAT}")
endif()
message(STATUS "Dat file name: ${CIRCUIT_DAT}")

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

message("USE_ASM=" ${USE_ASM})
message("CMAKE_CROSSCOMPILING=" ${CMAKE_CROSSCOMPILING})

message("GMP_PREFIX=" ${GMP_PREFIX})
message("GMP_INCLUDE_DIR=" ${GMP_INCLUDE_DIR})
message("GMP_LIB_DIR=" ${GMP_LIB_DIR})

if (NOT EXISTS ${GMP_INCLUDE_FILE_FULLPATH})
    message("WARNING: ${GMP_INCLUDE_FILE_FULLPATH} is not found and so system ${GMP_INCLUDE_FILE} is used.")
endif()

if (NOT EXISTS ${GMP_LIB_FILE_FULLPATH})
    message("WARNING: ${GMP_LIB_FILE_FULLPATH} is not found and so system ${GMP_LIB_FILE} is used.")
    set(GMP_LIB gmp)
endif()


include_directories(BEFORE ${GMP_INCLUDE_DIR})

add_subdirectory(src)

install(TARGETS
    tests
    test_platform
    ${CIRCUIT_FILE_NAME}
    witnesscalc_${CIRCUIT_FILE_NAME}
    witnesscalc_${CIRCUIT_FILE_NAME}Static
    fr
    RUNTIME DESTINATION ${CMAKE_INSTALL_PREFIX}/bin
    BUNDLE DESTINATION ${CMAKE_INSTALL_PREFIX}/app
    LIBRARY DESTINATION ${CMAKE_INSTALL_PREFIX}/lib)

install(FILES "${GMP_LIB_DIR}/${GMP_LIB_FILE}"
    DESTINATION ${CMAKE_INSTALL_PREFIX}/lib)

install(FILES
    ${CIRCUIT_DAT}
    DESTINATION ${CMAKE_INSTALL_PREFIX}/bin)

install(FILES
    ${CMAKE_BINARY_DIR}/generated/witnesscalc_${CIRCUIT_FILE_NAME}.h
    DESTINATION ${CMAKE_INSTALL_PREFIX}/include)
