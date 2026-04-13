include(FetchContent)

FetchContent_Declare(
  Catch2
  GIT_REPOSITORY https://github.com/catchorg/Catch2.git
  GIT_TAG v3.5.4
)
FetchContent_MakeAvailable(Catch2)

add_executable(adt_tests
  test_main.cpp
  test_invariants.cpp
  test_thermo_roundtrip.cpp
  test_benzene_toluene_column.cpp
  RunResultsParser.cpp
  test_column_runresults_regression.cpp
)

target_compile_features(adt_tests PRIVATE cxx_std_20)

# Link the core library so tests compile with the exact same code as the app
target_link_libraries(adt_tests PRIVATE adt_core Catch2::Catch2)

# Register with CTest (so Visual Studio Test Explorer / ctest can discover them)
include(Catch)
catch_discover_tests(adt_tests)

# Put the test exe in a predictable place (optional)
set_target_properties(adt_tests PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)

add_executable(thermo_regression
  thermo_regression_main.cpp
)

target_compile_features(thermo_regression PRIVATE cxx_std_20)
target_link_libraries(thermo_regression PRIVATE adt_core)
set_target_properties(thermo_regression PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)

add_executable(runresults_to_json
  RunResultsParser.cpp
  runresults_to_json_main.cpp
)

target_compile_features(runresults_to_json PRIVATE cxx_std_20)
set_target_properties(runresults_to_json PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)
