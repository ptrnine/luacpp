macro(git_submodule_build _project_name)
    if (NOT ${_project_name}_ALREADY_BUILT)
        set(options INSTALL_SUB_DEPS)
        set(oneValueArgs CMAKE_LISTS_DIR)
        set(multiValueArgs CMAKE_ARGS)
        cmake_parse_arguments(${_project_name} "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

        message("-- Build submodule '${_project_name}' at ${CMAKE_SOURCE_DIR}/submodules/${_project_name}")

        set(${_project_name}_command
                -G ${CMAKE_GENERATOR}
                .
                -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
                -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
                -DCMAKE_INSTALL_PREFIX=${CMAKE_BINARY_DIR}/3rd
                -B${CMAKE_BINARY_DIR}/submodules/${_project_name}
                )

        list(APPEND ${_project_name}_command ${${_project_name}_CMAKE_ARGS})

        execute_process(COMMAND ${CMAKE_COMMAND} ${${_project_name}_command}
                RESULT_VARIABLE result
                WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/submodules/${_project_name}/${${_project_name}_CMAKE_LISTS_DIR}
                )

        if(result)
            message(FATAL_ERROR "CMake step for ${_project_name} failed: ${result}")
        endif()

        if(DEFINED MAKE_NPROCS)
            set(MAKE_ARGS "-j${MAKE_NPROCS}")
        endif()

        execute_process(COMMAND ${CMAKE_COMMAND} --build . --target install "${MAKE_ARGS}"
                RESULT_VARIABLE result
                WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/submodules/${_project_name}
                )

        if(result)
            message(FATAL_ERROR "Build step for ${_project_name} failed: ${result}")
        endif()

        if (${_project_name}_INSTALL_SUB_DEPS)
            message("Install sub-dependenies of ${_project_name}...")

            file(COPY "${CMAKE_BINARY_DIR}/submodules/${_project_name}/3rd/" DESTINATION "${CMAKE_BINARY_DIR}/3rd/")
        endif()

        set(${_project_name}_ALREADY_BUILT ON CACHE STRING "Is submodule already built")
    else()
        message("-- Submodule '${_project_name}' at ${CMAKE_SOURCE_DIR}/submodules/${_project_name} already build")
    endif()

endmacro()

macro(git_submodule_make_build _project_name)
    if (NOT ${_project_name}_ALREADY_BUILT)
        message("-- Build submodule '${_project_name}' at ${CMAKE_SOURCE_DIR}/submodules/${_project_name}")

        set(oneValueArgs GIT_VERSION)
        set(multiValueArgs PATCHES)
        cmake_parse_arguments(${_project_name} "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

        # Checkout specified version
        execute_process(COMMAND git checkout "${${_project_name}_GIT_VERSION}"
                RESULT_VARIABLE result
                WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/submodules/${_project_name}"
        )

        if(result)
            message(FATAL_ERROR "Failed to checkout version ${${_project_name}_GIT_VERSION} ${_project_name}")
        endif()

        # Apply patches
        foreach(_patch ${${_project_name}_PATCHES})
            if ("${_patch}" MATCHES "\.in$")
                string(REPLACE ".in" "" _patch "${_patch}")
                configure_file("${CMAKE_SOURCE_DIR}/${_patch}.in" "${CMAKE_BINARY_DIR}/${_patch}" @ONLY)
                set(_patch_path "${CMAKE_BINARY_DIR}/${_patch}")
            else()
                set(_patch_path "${CMAKE_SOURCE_DIR}/${_patch}")
            endif()

            message("-- Apply patch ${_patch_path} for ${_project_name} submodule")

            execute_process(COMMAND git apply "${_patch_path}"
                WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/submodules/${_project_name}")
        endforeach()

        if (${_project_name}_PATCHES)
            execute_process(
                COMMAND
                    git commit --all --no-edit --no-gpg-sign -m "Patched from cmake"
                    --author="CMake Build <no@email>"
                RESULT_VARIABLE result
                WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/submodules/${_project_name}")
            if (result)
                message(WARNING "Can't commit changes in submodule ${_project_name}")
            endif()
        endif()

        file(GLOB ${_project_name}_files "${CMAKE_SOURCE_DIR}/submodules/${_project_name}/*")
        file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/submodules/${_project_name}")

        foreach(_file ${${_project_name}_files})
            if(NOT "${_file}" MATCHES "/\.git$")
                file(COPY ${_file} DESTINATION "${CMAKE_BINARY_DIR}/submodules/${_project_name}")
            endif()
        endforeach()

        if(DEFINED MAKE_NPROCS)
            set(MAKE_ARGS "-j${MAKE_NPROCS}")
        endif()

        set(ENV{CC} "${CMAKE_C_COMPILER}")
        execute_process(COMMAND make ${MAKE_ARGS} install DESTDIR="${CMAKE_BINARY_DIR}/3rd" PREFIX=
                RESULT_VARIABLE result
                WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/submodules/${_project_name}
        )
        if(result)
            message(FATAL_ERROR "CMake step for ${_project_name} failed: ${result}")
        endif()

        set(${_project_name}_ALREADY_BUILT ON CACHE STRING "Is submodule already built")
    else()
        message("-- Submodule '${_project_name}' at ${CMAKE_SOURCE_DIR}/submodules/${_project_name} already build")
    endif()
endmacro()

macro(git_submodule_copy_files _project_name)
    set(options NO_NAME_INCLUDE)
    set(oneValueArgs EXPLICIT_INCLUDE_NAME EXPLICIT_INCLUDE_DIR)
    set(multiValueArgs INCLUDES LIBRARIES)
    cmake_parse_arguments(${_project_name} "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if (${_project_name}_NO_NAME_INCLUDE AND DEFINED ${_project_name}_EXPLICIT_INCLUDE_NAME)
        message(FATAL_ERROR "Can't use NO_NAME_INCLUDE with EXPLICIT_INCLUDE_NAME")
    endif()

    if (${_project_name}_NO_NAME_INCLUDE AND DEFINED ${_project_name}_EXPLICIT_INCLUDE_DIR)
        message(FATAL_ERROR "Can't use NO_NAME_INCLUDE with EXPLICIT_INCLUDE_DIR")
    endif()

    if (DEFINED ${_project_name}_EXPLICIT_INCLUDE_DIR AND ${_project_name}_EXPLICIT_INCLUDE_NAME)
        message(FATAL_ERROR "Can't use EXPLICIT_INCLUDE_DIR with EXPLICIT_INCLUDE_NAME")
    endif()

    foreach(_file ${${_project_name}_INCLUDES})
        get_filename_component(_path ${_file} DIRECTORY)
        set(_src_path "${CMAKE_SOURCE_DIR}/submodules/${_project_name}/${_file}")
        set(_dst_path "${CMAKE_BINARY_DIR}/3rd/include")

        if(${_project_name}_NO_NAME_INCLUDE)
            file(COPY "${_src_path}" DESTINATION "${_dst_path}/${_path}")
        else()
            if (DEFINED ${_project_name}_EXPLICIT_INCLUDE_DIR)
                file(COPY "${_src_path}" DESTINATION "${_dst_path}/${${_project_name}_EXPLICIT_INCLUDE_DIR}")
            elseif (DEFINED ${_project_name}_EXPLICIT_INCLUDE_NAME)
                file(COPY "${_src_path}" DESTINATION "${_dst_path}/${${_project_name}_EXPLICIT_INCLUDE_NAME}/${_path}")
            else()
                file(COPY "${_src_path}" DESTINATION "${_dst_path}/${_project_name}/${_path}")
            endif()
        endif()
    endforeach()

    foreach(_file ${${_project_name}_LIBRARIES})
        get_filename_component(_path ${_file} DIRECTORY)
        file(COPY "${CMAKE_SOURCE_DIR}/submodules/${_project_name}/${_file}" DESTINATION "${CMAKE_BINARY_DIR}/3rd/lib/${_path}")
    endforeach()
endmacro()

macro(git_submodule_update)
    find_package(Git QUIET)
    if(GIT_FOUND AND EXISTS "${PROJECT_SOURCE_DIR}/.git")
        message(STATUS "Submodule update")
        execute_process(COMMAND ${GIT_EXECUTABLE} submodule update --init --recursive
                TIMEOUT 100000
                WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
                RESULT_VARIABLE GIT_SUBMOD_RESULT)
        if(NOT GIT_SUBMOD_RESULT EQUAL "0")
            message(FATAL_ERROR "git submodule update --init --recursive failed with ${GIT_SUBMOD_RESULT}, please checkout submodules")
        endif()
    else()
        message(FATAL_ERROR "Can't find git")
    endif()
endmacro()
