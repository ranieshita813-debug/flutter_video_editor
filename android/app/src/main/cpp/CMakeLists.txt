cmake_minimum_required(VERSION 3.18.1)

project("video_processor")

add_library(
        video_processor
        SHARED
        video_processor.cpp)

find_library(
        log-lib
        log)

target_link_libraries(
        video_processor
        ${log-lib})
