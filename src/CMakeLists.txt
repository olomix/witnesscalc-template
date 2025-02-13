include_directories(
    ../src
    ../build
    ../depends/json/single_include)

link_libraries(${GMP_LIB})

add_definitions(${GMP_DEFINIONS})

if(USE_ASM)
    if(ARCH MATCHES "arm64")
            add_definitions(-DUSE_ASM -DARCH_ARM64)
    elseif(ARCH MATCHES "x86_64")
            add_definitions(-DUSE_ASM -DARCH_X86_64)
    endif()
endif()

if(USE_ASM AND ARCH MATCHES "x86_64")

    if (CMAKE_HOST_SYSTEM_NAME MATCHES "Darwin" AND NOT TARGET_PLATFORM MATCHES "^android(_x86_64)?")
        set(NASM_FLAGS -fmacho64 --prefix _)
    else()
        set(NASM_FLAGS -felf64 -DPIC)
    endif()

    add_custom_command(OUTPUT ${CMAKE_SOURCE_DIR}/build/fq_asm.o
        COMMAND nasm ${NASM_FLAGS} fq.asm -o fq_asm.o
        DEPENDS ${CMAKE_SOURCE_DIR}/build/fq.asm
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/build)

    add_custom_command(OUTPUT ${CMAKE_SOURCE_DIR}/build/fr_asm.o
        COMMAND nasm ${NASM_FLAGS} fr.asm -o fr_asm.o
        DEPENDS ${CMAKE_SOURCE_DIR}/build/fr.asm
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/build)
endif()

set(FR_SOURCES
    ../build/fr.hpp
    ../build/fr.cpp
    )

if(USE_ASM)
    if(ARCH MATCHES "arm64")
        set(FR_SOURCES ${FR_SOURCES} ../build/fr_raw_arm64.s ../build/fr_raw_generic.cpp ../build/fr_generic.cpp)
    elseif(ARCH MATCHES "x86_64")
        set(FR_SOURCES ${FR_SOURCES} ../build/fr_asm.o)
    endif()
else()
    set(FR_SOURCES ${FR_SOURCES} ../build/fr_generic.cpp ../build/fr_raw_generic.cpp)
endif()

add_library(fr STATIC ${FR_SOURCES})
set_target_properties(fr PROPERTIES POSITION_INDEPENDENT_CODE ON)

link_libraries(fr)

add_executable(tests tests.cpp)
add_executable(test_platform test_platform.cpp)

set(LIB_SOURCES
    calcwit.cpp
    witnesscalc.h
    witnesscalc.cpp
)

set(CIRCUIT_PATCHED_FILE ${CMAKE_BINARY_DIR}/generated/${CIRCUIT_FILE_NAME}.cpp)
add_custom_command(
        OUTPUT ${CIRCUIT_PATCHED_FILE}
        COMMAND bash ${CMAKE_SOURCE_DIR}/patch_cpp.sh ${CIRCUIT_FILE} > ${CIRCUIT_PATCHED_FILE}
        DEPENDS ${CMAKE_SOURCE_DIR}/patch_cpp.sh ${CIRCUIT_FILE}
        COMMENT "Generating ${CIRCUIT_PATCHED_FILE}"
        VERBATIM
)

configure_file(
        ${CMAKE_SOURCE_DIR}/src/witnesscalc_circuit.h.in
        ${CMAKE_BINARY_DIR}/generated/witnesscalc_${CIRCUIT_FILE_NAME}.h
)

configure_file(
        ${CMAKE_SOURCE_DIR}/src/witnessclc_circuit.cpp.in
        ${CMAKE_BINARY_DIR}/generated/witnesscalc_${CIRCUIT_FILE_NAME}.cpp
)

set(CIRCUIT_SOURCES ${LIB_SOURCES}
    ${CIRCUIT_PATCHED_FILE}
    ${CMAKE_BINARY_DIR}/generated/witnesscalc_${CIRCUIT_FILE_NAME}.h
    ${CMAKE_BINARY_DIR}/generated/witnesscalc_${CIRCUIT_FILE_NAME}.cpp
)

add_library(witnesscalc_${CIRCUIT_FILE_NAME} SHARED ${CIRCUIT_SOURCES})
add_library(witnesscalc_${CIRCUIT_FILE_NAME}Static STATIC ${CIRCUIT_SOURCES})
set_target_properties(witnesscalc_${CIRCUIT_FILE_NAME}Static PROPERTIES OUTPUT_NAME witnesscalc_${CIRCUIT_FILE_NAME})

add_executable(${CIRCUIT_FILE_NAME} main.cpp)
target_link_libraries(${CIRCUIT_FILE_NAME} witnesscalc_${CIRCUIT_FILE_NAME}Static)

target_compile_definitions(witnesscalc_${CIRCUIT_FILE_NAME} PUBLIC CIRCUIT_NAME=${CIRCUIT_NAME})
target_compile_definitions(witnesscalc_${CIRCUIT_FILE_NAME}Static PUBLIC CIRCUIT_NAME=${CIRCUIT_NAME})
target_compile_definitions(${CIRCUIT_FILE_NAME} PUBLIC CIRCUIT_NAME=${CIRCUIT_NAME})
