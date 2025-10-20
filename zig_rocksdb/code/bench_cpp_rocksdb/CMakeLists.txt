cmake_minimum_required(VERSION 3.10)
project(bench_cpp_rocksdb)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_BUILD_TYPE Release)

find_package(Threads REQUIRED)

# Try to find RocksDB via typical name; if system has rocksdb-config.cmake this works.
find_package(RocksDB)
if (NOT RocksDB_FOUND)
    message(STATUS "RocksDB not found via CMake config; will link 'rocksdb' library name (system default).")
    add_library(rocksdb_import INTERFACE)
    target_include_directories(rocksdb_import INTERFACE /usr/include)
    set(ROCKSDB_LIB rocksdb)
else()
    set(ROCKSDB_LIB ${RocksDB_LIBRARIES})
    include_directories(${RocksDB_INCLUDE_DIRS})
endif()

add_executable(bench_cpp_rocksdb main.cpp)

if (TARGET rocksdb_import)
    target_link_libraries(bench_cpp_rocksdb PRIVATE rocksdb pthread)
else()
    target_link_libraries(bench_cpp_rocksdb PRIVATE ${ROCKSDB_LIB} Threads::Threads)
endif()
