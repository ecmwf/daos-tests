#!/bin/env bash

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


# USAGE: ./benchio/test_wrapper.sh <N_NODES> <DAOS_TEST_SCRIPT_NAME> <BENCHIO_API> <FABRIC_PROVIDER> <CLIENTS_PER_NODE> <REPS_PER_CLIENT> <WRITE_OR_READ> <REP_MODE> <UNIQUE> <UNIQUE_REP> <KEEP> <SLEEP> <OC> <OSIZE> <POOL> <CONT>

n_nodes=$1
#test_name=$2
benchio_api=$3
#fabric_provider=$4
clients_per_node=$5
reps_per_client=$6
write_or_read=$7  # either "write" or "read"
rep_mode="${8:-0}"  # one of the daosconfigs supported by benchio
#unique=$9
#unique_rep=${10}
#keep=${11}
#sleep=${12}
oc="${13:-S1}"
osize="${14:-1MiB}"
pool=${15}
cont=${16}

benchio_src=$HOME/benchio
benchio_shared_dir=$HOME/local/benchio

mpi_params=
benchio_params=()
#with_mpiio=
dfuse_path=/tmp/daos_store
#api_param="-a $benchio_api"
api_param=
keep_param=
[[ "$write_or_read" == "write" ]] && keep_param="keepdata"

export I_MPI_OFI_LIBRARY_INTERNAL=0
source /opt/intel/setvars.sh
#export I_MPI_ADJUST_BARRIER=2

if [[ "$benchio_api" == "DAOS" ]] ; then

	api_param="daos"
	benchio_params=("--daos.pool" "$pool" "--daos.cont" "$cont")
	[[ "${oc}" == "S1" ]] && benchio_params+=("unstriped")
	[[ "${oc}" == "SX" ]] && benchio_params+=("striped")

elif [[ "$benchio_api" == "DFUSE" ]] || [[ "$benchio_api" == "DFUSE_IL" ]] || \
	[[ "$benchio_api" == "MPIIO_DFUSE" ]] ; then

        benchio_params=("--file" "$dfuse_path/test" "unstriped")
	[[ "$benchio_api" == "DFUSE" ]] || [[ "$benchio_api" == "DFUSE_IL" ]] && \
		api_param="proc"
	#	ior_params+=" -O useO_DIRECT=1" && \
	mpi_params="-genv LD_PRELOAD="
	[[ "$benchio_api" == "DFUSE_IL" ]] && mpi_params="-genv LD_PRELOAD=/usr/lib64/libioil.so"

	mkdir -p $dfuse_path
	dfuse -m $dfuse_path --pool $pool --container $cont \
  		--disable-caching --thread-count=24 --eq-count=12

	if [[ "$benchio_api" == "MPIIO_DFUSE" ]] ; then

		api_param="mpiio"

	fi

else
	echo "Unsupported BenchIO API" && exit 1
fi














nodelist=($(python3 - "$SLURM_NODELIST" <<EOF
import sys
import re

if len(sys.argv) != 2:
  raise Exception("Expected 1 argument.")

s = sys.argv[1]

#s = "compute-b24-[1-3,5-9],compute-b22-1,compute-b23-[3],compute-b25-[1,4,8]"

blocks = re.findall(r'[^,\[]+(?:\[[^\]]*\])?', s)
r = []
for b in blocks:
  if '[' in b:
    parts = b.split('[')
    ranges = parts[1].replace(']', '').split(',')
    for i in ranges:
      if '-' in i:
        limits = i.split('-')
        digits = len(limits[0])
        for j in range(int(limits[0]), int(limits[1]) + 1):
          print(parts[0] + (("%0" + str(digits) + "d") % (j,)))
      else:
        print(parts[0] + i)
  else:
    print(b)
EOF
))

if [ $SLURM_NODEID -eq 0 ] ; then

        received=()
        for node in "${nodelist[@]}" ; do
                [[ "$node" == "$SLURMD_NODENAME" ]] && continue
                echo "WAITING FOR MESSAGE from other nodes"
                received+=($(ncat -l -p 12345 | bash -c 'read MESSAGE; echo $MESSAGE'))
        done

        a=($(printf '%s\n' "${nodelist[@]}" | sort))
        b=( "${nodelist[0]}" )
        b+=($(printf '%s\n' "${received[@]}" | sort))
        [[ "${a[@]}" == "${b[@]}" ]] && echo "Node configuration ended on all nodes" || \
                ( echo -e "Received unexpected messages while waiting for node configuration.\nExpected: ${a[@]}.\nReceived: ${b[@]}" )

else

        code=1
        while [ "$code" -ne 0 ] ; do
                echo "SENDING MESSAGE from $SLURMD_NODENAME to ${nodelist[0]}"
                echo "$SLURMD_NODENAME" | ncat ${nodelist[0]} 12345
                code=$?
                [ "$code" -ne 0 ] && sleep 2
        done

fi















if [ $SLURM_NODEID -eq 0 ] ; then

    benchio_build_dir=$benchio_shared_dir

    if [ ! -d $benchio_build_dir ] ; then
        if [ ! -d $benchio_src ] ; then
            mkdir $benchio_src
            cd $benchio_src
            git clone https://github.com/adrianjhpc/benchio.git .
	    git checkout gcp-runs
        fi
        cd $benchio_src
        make -f Makefile-gcp clean
        make -f Makefile-gcp
        mkdir -p $benchio_build_dir
        cp benchio $benchio_build_dir/
    fi

fi  #endif node 0

if [ $SLURM_NODEID -eq 0 ] ; then

	io_size_mb=${osize%MiB*}

        repeat=1
        if [ "$reps_per_client" -gt 100 ] ; then
                repeat=$(( $reps_per_client / 100 ))
                reps_per_client=100
        fi

	I_MPI_PIN_DOMAIN=auto I_MPI_PIN_CELL=unit I_MPI_PIN_ORDER=scatter \
	mpirun -n $(($clients_per_node * $n_nodes)) \
		-ppn $clients_per_node $mpi_params \
		-genv LD_LIBRARY_PATH=/home/daos-user/local/hdf5/lib \
		$benchio_build_dir/benchio 1 $reps_per_client $(( io_size_mb * 131072 )) $repeat \
		global $write_or_read $api_param "${benchio_params[@]}" $keep_param

	for node in "${nodelist[@]}" ; do
		[[ "$node" == "$SLURMD_NODENAME" ]] && continue
		code=1
		while [ "$code" -ne 0 ] ; do
			echo "SENDING MESSAGE from $SLURMD_NODENAME to $node"
			echo "BenchIO build and launch on $SLURMD_NODENAME ended" | ncat $node 12345
			code=$?
			[ "$code" -ne 0 ] && sleep 2
		done
	done

else

	echo "WAITING FOR MESSAGE from $SLURMD_NODENAME"
	ncat -l -p 12345 | bash -c 'read MESSAGE; echo "${SLURMD_NODENAME}": $MESSAGE'

fi

if [[ "$benchio_api" == "DFUSE" ]] || [[ "$benchio_api" == "DFUSE_IL" ]] || \
	[[ "$benchio_api" == "MPIIO_DFUSE" ]] ; then

	sudo umount $dfuse_path

fi
