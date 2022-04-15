# Copyright 2022 European Centre for Medium-Range Weather Forecasts (ECMWF)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# In applying this licence, ECMWF does not waive the privileges and immunities
# granted to it by virtue of its status as an intergovernmental organisation nor
# does it submit to any jurisdiction.

cmake_minimum_required( VERSION 3.12 FATAL_ERROR )

find_package( ecbuild 3.4 REQUIRED HINTS ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/../ecbuild)

project( daos_field_io LANGUAGES C )

#set(CMAKE_CXX_STANDARD 11)
#set(CMAKE_CXX_STANDARD_REQUIRED ON)

ecbuild_add_option( FEATURE PROFILING
		    DEFAULT OFF
		    DESCRIPTION "Profile each DAOS API call" )

ecbuild_add_option( FEATURE SIMPLIFIED
		    DEFAULT OFF
		    DESCRIPTION "Use simplified version of field IO functions without indexing (single container and arrays only)" )

ecbuild_add_option( FEATURE SIMPLIFIED_KVS
		    DEFAULT OFF
		    DESCRIPTION "Use simplified version of field IO functions without container layers (with indexing and using a single container for all kvs and arrays)" )

set( DAOS_FIELD_IO_OC_MAIN_KV "OC_SX" CACHE STRING "main kv object class" )
set( DAOS_FIELD_IO_OC_INDEX_KV "OC_S2" CACHE STRING "index kv object class" )
set( DAOS_FIELD_IO_OC_STORE_ARRAY "OC_S1" CACHE STRING "store array object class" )

include(cmake/compiler_warnings.cmake) # optionally handle compiler specific warnings

find_package(DAOS)
find_package(UUID)

add_subdirectory( src )
add_subdirectory( share )

ecbuild_pkgconfig( NAME daos_field_io
		   DESCRIPTION "Library for weather field IO from/to DAOS" 
		   LIBRARIES daos_field_io )

ecbuild_install_project( NAME ${PROJECT_NAME} )

ecbuild_print_summary()
