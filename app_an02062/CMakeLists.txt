cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(app_an02062)

set(APP_HW_TARGET XK-EVK-XU316)

set(APP_INCLUDES src src/eth_tcp)

set(APP_COMPILER_FLAGS -O3 -g -report -DUSE_XSCOPE=1 -fxscope)

set (APP_DEPENDENT_MODULES "lib_xud(4.0.1)"
                           "lib_logging(3.5.0)"
                           "lib_xassert(5.1.0)"
                          )

set(XMOS_SANDBOX_DIR ${CMAKE_CURRENT_LIST_DIR}/../..)

XMOS_REGISTER_APP()
