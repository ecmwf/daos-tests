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

ecbuild_add_option( FEATURE WARNINGS
		    DEFAULT ON
		    DESCRIPTION "Add warnings to compiler" )

# activate warnings, ecbuild macros check the compiler recognises the options
if(HAVE_WARNINGS)

  ecbuild_add_c_flags("-Wall")
  ecbuild_add_c_flags("-Wextra")

  if(CMAKE_C_COMPILER_ID MATCHES "GNU")
    ecbuild_add_c_flags("-Wno-unused-parameter")
    ecbuild_add_c_flags("-Wno-unused-variable")
    ecbuild_add_c_flags("-Wno-sign-compare")
  endif()

  if(CMAKE_C_COMPILER_ID MATCHES "Clang")
    ecbuild_add_c_flags("-Wno-unused-parameter")
    ecbuild_add_c_flags("-Wno-unused-variable")
    ecbuild_add_c_flags("-Wno-sign-compare")
  endif()

  #ecbuild_add_cxx_flags("-Wall")
  #ecbuild_add_cxx_flags("-Wextra")

  #if(CMAKE_CXX_COMPILER_ID MATCHES "GNU")
  #  ecbuild_add_cxx_flags("-Wno-unused-parameter")
  #  ecbuild_add_cxx_flags("-Wno-unused-variable")
  #  ecbuild_add_cxx_flags("-Wno-sign-compare")
  #endif()

  #if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  #  ecbuild_add_cxx_flags("-Wno-unused-parameter")
  #  ecbuild_add_cxx_flags("-Wno-unused-variable")
  #  ecbuild_add_cxx_flags("-Wno-sign-compare")
  #endif()

endif()
