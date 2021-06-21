
cmake_minimum_required(VERSION 3.2 FATAL_ERROR)
project(trace_stream_loader VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(SDE_LIB_PATH $ENV{SDE_INSTALL}/lib)
set(THREADS_PREFER_PTHREAD_FLAG ON)

include(GNUInstallDirs)

include_directories($ENV{SDE_INSTALL}/include/)

find_package(Threads REQUIRED)

include(gmp.cmake)

find_library(PYTHON_LIBRARY libpython3.4m.so PATHS ${SDE_LIB_PATH})
find_library(AVAGO_LIBRARY libavago.so PATHS ${SDE_LIB_PATH})
find_library(TOFINOPDFIXED_LIBRARY libtofinopdfixed_thrift.so PATHS ${SDE_LIB_PATH})
find_library(BF_SWITCHD_LIBRARY libbf_switchd_lib.so PATHS ${SDE_LIB_PATH})
find_library(DRIVER_LIBRARY libdriver.so PATHS ${SDE_LIB_PATH})
find_library(BFSYS_LIBRARY libbfsys.so PATHS ${SDE_LIB_PATH})
find_library(BFUTILS_LIBRARY libbfutils.so PATHS ${SDE_LIB_PATH})

add_executable(run_controlplane_pie src/run_controlplane_pie.cpp)

target_link_libraries(run_controlplane_pie Threads::Threads gmp gmpxx)

target_link_libraries(run_controlplane_pie
    ${PYTHON_LIBRARY} ${AVAGO_LIBRARY} ${TOFINOPDFIXED_LIBRARY} ${BF_SWITCHD_LIBRARY} ${DRIVER_LIBRARY} ${BFSYS_LIBRARY} ${BFUTILS_LIBRARY})
