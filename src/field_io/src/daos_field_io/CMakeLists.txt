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

ecbuild_generate_config_headers( DESTINATION ${INSTALL_INCLUDE_DIR}/daos_field_io )

configure_file( daos_field_io_config.h.in daos_field_io_config.h )
configure_file( daos_field_io_version.h.in daos_field_io_version.h )
configure_file( daos_field_io_version.c.in daos_field_io_version.c )

install(FILES
		${CMAKE_CURRENT_BINARY_DIR}/daos_field_io_config.h
		${CMAKE_CURRENT_BINARY_DIR}/daos_field_io_version.h
	DESTINATION
		${INSTALL_INCLUDE_DIR}/daos_field_io )

list( APPEND daos_field_io_srcs
	daos_field_io.c
	daos_field_io.h
	daos_field_io_version.c )

ecbuild_add_library(

	TARGET daos_field_io

	INSTALL_HEADERS LISTED

	HEADER_DESTINATION ${INSTALL_INCLUDE_DIR}/daos_field_io

	GENERATED daos_field_io_version.c

	SOURCES ${daos_field_io_srcs}

	PUBLIC_INCLUDES
		$<BUILD_INTERFACE:${PROJECT_BINARY_DIR}/src/daos_field_io>
		$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/src/daos_field_io>

	PRIVATE_LIBS daos gurt daos_common

)
