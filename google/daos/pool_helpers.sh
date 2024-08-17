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

cont_create_args=
[[ "$posix_cont" == "true" ]] && cont_create_args="--type=POSIX"

[[ "$servers" == "single_server" ]] && pool="one_server"
[[ "$servers" == "dual_server" ]] && echo "Not implemented" && return 1
# for DFS_OLD and HDF5
#[[ "$servers" == "quad_server" ]] && pool="be1a8241-c1d7-44ec-82d8-5b2ea149196d"
[[ "$servers" == "quad_server" ]] && pool="four_server"
[[ "$servers" == "hexa_server" ]] && echo "Not implemented" && return 1
[[ "$servers" == "octa_server" ]] && pool="eight_server"
[[ "$servers" == "ten_server" ]] && echo "Not implemented" && return 1
[[ "$servers" == "twelve_server" ]] && pool="twelve_server"
[[ "$servers" == "fourteen_server" ]] && echo "Not implemented" && return 1
[[ "$servers" == "sixteen_server" ]] && pool="sixteen_server"
[[ "$servers" == "twenty_server" ]] && pool="twenty_server"
[[ "$servers" == "twentyfour_server" ]] && pool="twentyfour_server"

[[ "$pool" == "" ]] && echo "Number of servers not recognised" && return 1


cat > cpool.sh <<EOF
#!/bin/env bash

#SBATCH --job-name=cpool
#SBATCH --output=cpool.log
#SBATCH --error=cpool.log
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --ntasks-per-core=1
#SBATCH --no-requeue
#SBATCH --exclusive
#SBATCH --time=0:05:00

# Set up logging for debugging.
export D_LOG_MASK=INFO
export D_LOG_FILE_APPEND_PID=1
rm -f /tmp/client.log.*
export D_LOG_FILE=/tmp/client.log

export pool_id="$pool"

dfs_dir_oclass=$dfs_oclass
[[ $dfs_oclass == "EC_"* ]] && dfs_dir_oclass="RP_2G${dfs_oclass#*G}"

out=\$(daos container create $pool testcont $cont_create_args --properties rd_fac:0,ec_cell_sz:128KiB --oclass $dfs_oclass --dir-oclass \$dfs_dir_oclass --file-oclass $dfs_oclass)
code=\$?
[ \$code -ne 0 ] && echo "\${out}" && exit 1
export cont_id=\$(echo "\$out" | grep "UUID" | awk '{print \$4}')

echo "CONT_CREATE_ARGS: $cont_create_args"
echo "POOL: \$pool_id"
echo "CONT: \$cont_id"

EOF

local out=$(sbatch cpool.sh)

local jid=$(echo "$out" | grep "Submitted batch job" | awk '{print $4}')

if [ -z "$jid" ] ; then

    code=1

else

    while squeue | grep -q -e "^ *$jid .* ${USER::8} " ; do sleep 5 && echo "Creating..."; done
    ls  # used to circumvent cpool.log not found
    out=$(cat cpool.log | grep "CONT_CREATE_ARGS:")
    code=$?
    cat cpool.log

fi

#rm slurm-${jid}.out nodefile.${jid} prepjob.${jid}.sh prolog_slurmd.${jid}.*
rm cpool.log
rm cpool.sh

fi

return $code

}

function destroy_pool_cont {

local on_posix=$1
local servers=$2
local test_name=${3:-field_io}

local code=0

[[ "$servers" == "single_server" ]] && pool="one_server"
[[ "$servers" == "dual_server" ]] && echo "Not implemented" && return 1
[[ "$servers" == "quad_server" ]] && pool="four_server"
[[ "$servers" == "hexa_server" ]] && echo "Not implemented" && return 1
[[ "$servers" == "octa_server" ]] && pool="eight_server"
[[ "$servers" == "ten_server" ]] && echo "Not implemented" && return 1
[[ "$servers" == "twelve_server" ]] && pool="twelve_server"
[[ "$servers" == "fourteen_server" ]] && echo "Not implemented" && return 1
[[ "$servers" == "sixteen_server" ]] && pool="sixteen_server"
[[ "$servers" == "twenty_server" ]] && pool="twenty_server"
[[ "$servers" == "twentyfour_server" ]] && pool="twentyfour_server"

[[ "$pool" == "" ]] && echo "Number of servers not recognised" && return 1


cat > dpool.sh <<EOF
#!/bin/env bash

#SBATCH --job-name=dpool
#SBATCH --output=dpool.log
#SBATCH --error=dpool.log
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --ntasks-per-core=1
#SBATCH --no-requeue
#SBATCH --exclusive
#SBATCH --time=0:05:00

# Set up logging for debugging.
export D_LOG_MASK=INFO
export D_LOG_FILE_APPEND_PID=1
rm -f /tmp/client.log.*
export D_LOG_FILE=/tmp/client.log

export pool_id="$pool"

daos container destroy $pool testcont
daos pool list-containers $pool | tail -n +3 | awk '{print \$1}' | xargs -I{} daos container destroy -f $pool {}
daos pool list-containers $pool

EOF

local out=$(sbatch dpool.sh)

local jid=$(echo "$out" | grep "Submitted batch job" | awk '{print $4}')

if [ -z "$jid" ] ; then

    code=1

else

    while squeue | grep -q -e "^ *$jid .* ${USER::8} " ; do sleep 5 && echo "Destroying..."; done
    ls  # used to circumvent cpool.log not found
    #out=$(cat dpool.log | grep "Successfully destroyed container")
    out=$(cat dpool.log | grep "No containers")
    echo "${out}"
    code=$?

fi

#rm slurm-${jid}.out nodefile.${jid} prepjob.${jid}.sh prolog_slurmd.${jid}.*
rm dpool.log
rm dpool.sh


return $code

}
