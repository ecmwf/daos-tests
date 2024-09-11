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

function create_pool_cont {

local posix_cont=$1
local on_posix=$2
local servers=$3
local test_name=${4:-field_io}  # either fdb_hammer or field_io
local dfs_oclass=${5:-S1}

local code=0

if [[ "$on_posix" == "true" ]] ; then

    local pool_param="--pool newlust."
    [[ "$servers" == "single_server" ]] && pool_param+="1nodes"
    [[ "$servers" == "dual_server" ]] && pool_param+="2nodes"
    [[ "$servers" == "quad_server" ]] && pool_param+="4nodes"
    [[ "$servers" == "hexa_server" ]] && echo "Not implemented" && return 1
    [[ "$servers" == "octa_server" ]] && pool_param+="8nodes"
    [[ "$servers" == "ten_server" ]] && pool_param+="10nodes"
    [[ "$servers" == "twelve_server" ]] && pool_param=
    [[ "$servers" == "fourteen_server" ]] && pool_param+="14nodes"
    [[ "$servers" == "sixteen_server" ]] && pool_param=
    pool_param=

    local mount_dir=/newlust
    local ready=0
    while [ $ready -eq 0 ] ; do
      local available=$(getent ahostsv4 mystore-manager | wc -l)
      [ $available -eq 0 ] && echo "Waiting for store manager to become available..." && sleep 30 && continue
      local mounted=$(mount -l | grep "${mount_dir} on ${mount_dir}" | wc -l)
      if [ $mounted -ne 0 ] ; then
	echo "Umounting Lustre..."
        sudo umount -l ${mount_dir}
        [ $? -ne 0 ] && echo "Umount failed. Waiting..." && sleep 10 && continue
      fi
      local mgsip="$(getent ahostsv4 mystore-manager | grep RAW | awk '{print $1}')@tcp"
      sudo mkdir -p $mount_dir
      sudo chmod 777 $mount_dir
      echo "Mounting Lustre..."
      sudo timeout 6 mount -t lustre ${mgsip}:${mount_dir} ${mount_dir}
      [ $? -ne 0 ] && echo "Mount failed or took too long. Waiting..." && sleep 30 && continue
      sudo chmod 777 $mount_dir
      # only if deploying more than one MDT. -c is the number of MDTs
      #sudo lfs setdirstripe -D -c 16 -i -1 $mount_dir
      ready=1
    done

    local test_dir=${mount_dir}/test_${test_name}_tmp

    mkdir -p ${test_dir}
    lfs setstripe -c -1 ${pool_param} ${test_dir}
    code=$?

    # for both dummy daos field I/O and fdb-hammer on posix we create a pool ID
    local rand1=$(od -An -N3 -i /dev/random)
    local rand2=$(od -An -N3 -i /dev/random)
    rand1=$(printf "%08d" $rand1)
    rand2=$(printf "%012d" $rand2)
    local pool_id="${rand1}-0000-0000-0000-${rand2}"

    echo "POOL: $pool_id"

fi

return $code

}

function destroy_pool_cont {

local on_posix=$1
local servers=$2
local test_name=${3:-field_io}

local code=0

if [[ "$on_posix" == "true" ]] ; then

    local test_dir=/newlust/test_${test_name}_tmp

    rm -rf ${test_dir}
    code=$?

fi

return $code

}
