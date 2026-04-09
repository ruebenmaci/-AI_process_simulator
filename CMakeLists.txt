cmake_minimum_required(VERSION 3.16)
project(chatgpt5_adt_simulation_qt LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# TEMP: force Qt for Visual Studio (remove after it configures)
set(Qt6_DIR "C:/Qt/6.10.1/msvc2022_64/lib/cmake/Qt6" CACHE PATH "" FORCE)
list(PREPEND CMAKE_PREFIX_PATH "C:/Qt/6.10.1/msvc2022_64")

find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 Concurrent)
qt_standard_project_setup(REQUIRES 6.2)

# ----------------------------
# Core (solver/thermo) library
# ----------------------------
add_library(adt_core
  cpp/thermo/Flash.cpp
  cpp/thermo/EOSK.cpp
  cpp/thermo/Enthalpy.cpp
  cpp/thermo/Entropy.cpp
  cpp/thermo/PH_PS_PT_TS_Flash.cpp
  cpp/thermo/StreamPropertyCalcs.cpp
  cpp/thermo/ThermoConfig.cpp
  cpp/thermo/eos/PR.cpp
  cpp/thermo/eos/SRK.cpp
  cpp/thermo/eos/PRSV.cpp
  cpp/thermo/pseudocomponents/componentData.cpp
  cpp/thermo/pseudocomponents/loaders.cpp
  cpp/thermo/pseudocomponents/FluidDefinition.cpp
  cpp/thermo/pseudocomponents/pseudoComponents.cpp
  cpp/unitops/column/config/CrudeInitialSettings.cpp
  cpp/unitops/column/sim/CounterCurrentColumnSimulator.cpp
  cpp/unitops/column/sim/ColumnSolver.cpp
)

# Your solver code is already using C++20 in places; make it explicit.
target_compile_features(adt_core PUBLIC cxx_std_20)

# Export ALL include paths needed by solver headers.
target_include_directories(adt_core PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}
  ${CMAKE_CURRENT_SOURCE_DIR}/cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/cpp/unitops
  ${CMAKE_CURRENT_SOURCE_DIR}/cpp/unitops/column
  ${CMAKE_CURRENT_SOURCE_DIR}/cpp/unitops/column/sim
  ${CMAKE_CURRENT_SOURCE_DIR}/cpp/unitops/column/config
  ${CMAKE_CURRENT_SOURCE_DIR}/cpp/unitops/column/thermo
  ${CMAKE_CURRENT_SOURCE_DIR}/cpp/unitops/column/thermo/eos
  ${CMAKE_CURRENT_SOURCE_DIR}/cpp/unitops/column/thermo/pseudocomponents
)

# ----------------------------
# Qt App
# ----------------------------
qt_add_executable(appChatGPT5_ADT
    cpp/main.cpp
    cpp/components/ComponentRecord.h
    cpp/components/ComponentRecord.cpp
    cpp/fluid/FluidPackageRecord.h
    cpp/fluid/FluidPackageRecord.cpp
    cpp/components/ComponentListRecord.h
    cpp/components/ComponentListRecord.cpp
    cpp/components/ComponentManager.h
    cpp/components/ComponentManager.cpp
    cpp/components/models/CompGroupListModel.h
    cpp/components/models/CompGroupListModel.cpp
    cpp/fluid/FluidPackageManager.h
    cpp/fluid/FluidPackageManager.cpp
    cpp/components/models/ComponentListModel.h
    cpp/components/models/ComponentListModel.cpp
    cpp/fluid/models/FluidPackageListModel.h
    cpp/fluid/models/FluidPackageListModel.cpp
    cpp/flowsheet/UnitNode.h
    cpp/flowsheet/models/FlowsheetUnitModel.h
    cpp/flowsheet/models/FlowsheetUnitModel.cpp
    cpp/flowsheet/state/FlowsheetState.h
    cpp/AppTheme.h
    cpp/flowsheet/state/FlowsheetState.cpp
    cpp/flowsheet/state/ProcessUnitState.h
    cpp/flowsheet/state/ProcessUnitState.cpp
    cpp/streams/state/MaterialStreamState.h
    cpp/streams/state/MaterialStreamState.cpp
    cpp/streams/models/StreamCompositionModel.h
    cpp/streams/models/StreamCompositionModel.cpp
    cpp/streams/state/StreamUnitState.h
    cpp/streams/state/StreamUnitState.cpp
    cpp/unitops/column/state/ColumnUnitState.h
    cpp/unitops/column/state/ColumnUnitState.cpp
    cpp/unitops/column/models/TrayModel.h
    cpp/unitops/column/models/TrayModel.cpp
    cpp/unitops/column/models/DiagnosticsModel.h
    cpp/unitops/column/models/DiagnosticsModel.cpp
    cpp/unitops/column/models/RunLogModel.h
    cpp/unitops/column/models/RunLogModel.cpp
    cpp/unitops/column/models/MaterialBalanceModel.h
    cpp/unitops/column/models/MaterialBalanceModel.cpp
)

qt_add_qml_module(appChatGPT5_ADT
    URI ChatGPT5.ADT
    VERSION 1.0
    NO_CACHEGEN
    QML_FILES
        qml/Main.qml
        qml/common/ClassicTabs.qml
        qml/common/ClassicButton.qml
        qml/pfd/PfdMainView.qml
        qml/pfd/PfdCanvas.qml
        qml/pfd/EquipmentPalette.qml
        qml/pfd/UnitNodeItem.qml
        qml/pfd/FloatingPanel.qml
        qml/components/ComponentManagerView.qml
        qml/fluid/FluidManagerView.qml
        qml/displaySettings/DisplaySettingsPanel.qml
        cpp/unitops/column/qml/ColumnWorkspaceWindow.qml
        cpp/unitops/column/qml/DistillationColumn.qml
        cpp/streams/qml/StreamView.qml
        cpp/streams/qml/StreamCompositionPanel.qml
        cpp/streams/qml/StreamConditionsPanel.qml
        cpp/streams/qml/StreamPhasesPanel.qml
        cpp/streams/qml/StreamPropertiesPanel.qml
        cpp/streams/qml/StreamWorkspaceWindow.qml
        qml/spreadsheet/SimpleSpreadsheet.qml
        qml/spreadsheet/SpreadsheetView.qml
        qml/spreadsheet/SpreadsheetWorkspaceWindow.qml
    RESOURCES
        icons/svg/Equip_Palette/Default/Distillation_Column.svg
        icons/svg/Equip_Palette/Default/Material_Stream.svg
        icons/svg/Equip_Palette/HYSYS/Distillation_Column.svg
        icons/svg/Equip_Palette/HYSYS/Material_Stream.svg
        icons/svg/Equip_Palette/AspenPlus/Distillation_Column.svg
        icons/svg/Equip_Palette/AspenPlus/Material_Stream.svg
        icons/svg/2D_Light_Icons/absorber.svg
        icons/svg/2D_Light_Icons/adsorber.svg
        icons/svg/2D_Light_Icons/batch_reactor.svg
        icons/svg/2D_Light_Icons/centrifuge.svg
        icons/svg/2D_Light_Icons/dist_column.svg
        icons/svg/2D_Light_Icons/component_list.svg
        icons/svg/2D_Light_Icons/compressor.svg
        icons/svg/2D_Light_Icons/condenser.svg
        icons/svg/2D_Light_Icons/cooler.svg
        icons/svg/2D_Light_Icons/cstr.svg
        icons/svg/2D_Light_Icons/cyclone.svg
        icons/svg/2D_Light_Icons/column.svg
        icons/svg/2D_Light_Icons/expander.svg
        icons/svg/2D_Light_Icons/filter.svg
        icons/svg/2D_Light_Icons/fired_heater.svg
        icons/svg/2D_Light_Icons/flash_drum.svg
        icons/svg/2D_Light_Icons/fluid_package.svg
        icons/svg/2D_Light_Icons/heat_exchanger.svg
        icons/svg/2D_Light_Icons/heater.svg
        icons/svg/2D_Light_Icons/hen.svg
        icons/svg/2D_Light_Icons/kettle_vaporizer.svg
        icons/svg/2D_Light_Icons/mixer.svg
        icons/svg/2D_Light_Icons/pid_controller.svg
        icons/svg/2D_Light_Icons/pipe_segment.svg
        icons/svg/2D_Light_Icons/plate_heat_exchanger.svg
        icons/svg/2D_Light_Icons/pump.svg
        icons/svg/2D_Light_Icons/reboiler.svg
        icons/svg/2D_Light_Icons/recycle.svg
        icons/svg/2D_Light_Icons/sensor.svg
        icons/svg/2D_Light_Icons/shortcut_column.svg
        icons/svg/2D_Light_Icons/stream_energy.svg
        icons/svg/2D_Light_Icons/stream_material.svg
        icons/svg/2D_Light_Icons/stripper.svg
        icons/svg/2D_Light_Icons/tee_splitter.svg
        icons/svg/2D_Light_Icons/three_phase_flash.svg
        icons/svg/2D_Light_Icons/valve.svg
        cpp/components/data/hydrocarbon_starter_components.json
)
# Link core into the Qt app (no Qt linkage needed in adt_core unless you use Qt types inside solver sources)
target_link_libraries(appChatGPT5_ADT
    PRIVATE
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::Concurrent
        adt_core
        dwmapi
)

# Keep these if app includes headers by short name; harmless because adt_core exports them too.
target_include_directories(appChatGPT5_ADT PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/cpp/unitops
)

# Helpful for Visual Studio/Qt VS Tools
set_target_properties(appChatGPT5_ADT PROPERTIES
    WIN32_EXECUTABLE TRUE
)

# ----------------------------
# Tests
# ----------------------------
include(CTest)
enable_testing()

option(ENABLE_TESTS "Build test harness" ON)

if (ENABLE_TESTS AND BUILD_TESTING)
  add_subdirectory(tests)
endif()