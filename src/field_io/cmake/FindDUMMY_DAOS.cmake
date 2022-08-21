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

include(FindPackageHandleStandardArgs)

# daos

find_path(DUMMY_DAOS_INCLUDE_DIR
    NAMES daos.h
    HINTS
        ${FDB5_ROOT}
        ${FDB5_DIR}
        ${FDB5_PATH}
        ENV FDB5_ROOT
        ENV FDB5_DIR
        ENV FDB5_PATH
    PATH_SUFFIXES include
)

find_library(DUMMY_DAOS_LIBRARY
    NAMES daos
    HINTS
        ${FDB5_ROOT}
        ${FDB5_DIR}
        ${FDB5_PATH}
        ENV FDB5_ROOT
        ENV FDB5_DIR
        ENV FDB5_PATH
    PATH_SUFFIXES lib lib64
)

# fdb5

find_library(ECKIT_LIBRARY
    NAMES eckit
    HINTS
        ${FDB5_ROOT}
        ${FDB5_DIR}
        ${FDB5_PATH}
        ENV FDB5_ROOT
        ENV FDB5_DIR
        ENV FDB5_PATH
    PATH_SUFFIXES lib lib64
)

find_package_handle_standard_args(
    DUMMY_DAOS
    DEFAULT_MSG
    DUMMY_DAOS_LIBRARY
    DUMMY_DAOS_INCLUDE_DIR
    ECKIT_LIBRARY )

mark_as_advanced(DUMMY_DAOS_INCLUDE_DIR DUMMY_DAOS_LIBRARY ECKIT_LIBRARY)

if(DUMMY_DAOS_FOUND)
    add_library(daos UNKNOWN IMPORTED GLOBAL)
    set_target_properties(daos PROPERTIES
        IMPORTED_LOCATION ${DUMMY_DAOS_LIBRARY}
        INTERFACE_INCLUDE_DIRECTORIES ${DUMMY_DAOS_INCLUDE_DIR}
    )
    add_library(eckit UNKNOWN IMPORTED GLOBAL)
    set_target_properties(eckit PROPERTIES
        IMPORTED_LOCATION ${ECKIT_LIBRARY}
        INTERFACE_INCLUDE_DIRECTORIES ${DUMMY_DAOS_INCLUDE_DIR}
    )
endif()
