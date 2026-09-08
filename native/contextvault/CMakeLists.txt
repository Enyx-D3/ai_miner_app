cmake_minimum_required(VERSION 3.22)
project(brain2_contextvault LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
add_library(contextvault SHARED
  src/atomizer.cpp
  src/builder.cpp
  src/c_api.cpp
  src/codec.cpp
  src/io.cpp
  src/predictor.cpp
  src/tokenizer.cpp
  src/txt_importer.cpp
  wasm/contextvault_browser_lib.cpp
  src/contextvault_mobile_ffi.cpp
)
target_include_directories(contextvault PRIVATE include src wasm)
if(ANDROID)
  find_library(LOG_LIB log)
  if(LOG_LIB)
    target_link_libraries(contextvault PRIVATE ${LOG_LIB})
  endif()
endif()
set_target_properties(contextvault PROPERTIES OUTPUT_NAME contextvault)
