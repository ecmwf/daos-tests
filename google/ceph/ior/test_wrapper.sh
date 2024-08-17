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


# USAGE: ./ior/test_wrapper.sh <N_NODES> <DAOS_TEST_SCRIPT_NAME> <IOR_API> <FABRIC_PROVIDER> <CLIENTS_PER_NODE> <REPS_PER_CLIENT> <WRITE_OR_READ> <REP_MODE> <UNIQUE> <UNIQUE_REP> <KEEP> <SLEEP> <OC> <POOL> <CONT>

n_nodes=$1
test_name=$2
ior_api=$3
fabric_provider=$4
clients_per_node=$5
reps_per_client=$6
write_or_read=$7  # either "write" or "read"
rep_mode="${8:-rep}"  # either "rep" or "segment"
unique=$9
unique_rep=${10}
keep=${11}
sleep=${12}
oc="${13:-S1}"
osize="${14:-1MiB}"
pool=${15}
cont=${16}

ior_src=$HOME/ior
ior_shared_dir=$HOME/local/ior

mpi_params=
ior_params=
with_mpiio=
api_param="-a $ior_api"

export I_MPI_OFI_LIBRARY_INTERNAL=0
source /opt/intel/setvars.sh

ior_params="-o test --rados.user admin --rados.conf $HOME/.ceph/ceph.conf --rados.pool $pool"










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

#if [ $SLURM_NODEID -eq 0 ] ; then
#
#        received=()
#        for node in "${nodelist[@]}" ; do
#                [[ "$node" == "$SLURMD_NODENAME" ]] && continue
#                echo "WAITING FOR MESSAGE from other nodes"
#                received+=($(ncat -l -p 12345 | bash -c 'read MESSAGE; echo $MESSAGE'))
#        done
#
#        a=($(printf '%s\n' "${nodelist[@]}" | sort))
#        b=( "${nodelist[0]}" )
#        b+=($(printf '%s\n' "${received[@]}" | sort))
#        [[ "${a[@]}" == "${b[@]}" ]] && echo "Node configuration ended on all nodes" || \
#                ( echo -e "Received unexpected messages while waiting for node configuration.\nExpected: ${a[@]}.\nReceived: ${b[@]}" )
#
#else
#
#        code=1
#        while [ "$code" -ne 0 ] ; do
#                echo "SENDING MESSAGE from $SLURMD_NODENAME to ${nodelist[0]}"
#                echo "$SLURMD_NODENAME" | ncat ${nodelist[0]} 12345
#                code=$?
#                [ "$code" -ne 0 ] && sleep 2
#        done
#
#fi



















if [ $SLURM_NODEID -eq 0 ] ; then

    ior_build_dir=$ior_shared_dir/${ior_api}

    if [ ! -d $ior_build_dir ] ; then
    if [ ! -d $ior_src ] ; then
        mkdir $ior_src
        cd $ior_src
        git clone https://github.com/hpc/ior.git .
    fi
    cd $ior_src
    make distclean
    ./bootstrap
    ./configure --with-cuda=no --with-rados --prefix=$ior_build_dir
    make
    make install
    fi  #endif no build dir

fi  #endif node 0

test_src_dir=$HOME/daos-tests

if [ $SLURM_NODEID -eq 0 ] ; then

	rw_params=
	[[ "$write_or_read" == "write" ]] && rw_params="-w"
	[[ "$write_or_read" == "read" ]] && rw_params="-r"

	unique_rep_param=
	[[ "$unique_rep" == "true" ]] && unique_rep_param="-m"

	rep_params=
	[[ "$rep_mode" == "rep" ]] && rep_params="-s 1 -i $reps_per_client $unique_rep_param"
	[[ "$rep_mode" == "segment" ]] && rep_params="-s $reps_per_client"
	#[[ "$rep_mode" == "segment" ]] && rep_params="-s $reps_per_client -i 100 -m"

	unique_param=
	[[ "$unique" == "true" ]] && unique_param="-F"	

	keep_param=
	[[ "$keep" == "true" ]] && keep_param="-k"

	# if willing to bind clients to a specific socket, e.g. --bind-to ib0
	#I_MPI_PIN_DOMAIN=auto I_MPI_PIN_ORDER=scatter I_MPI_PIN_CELL=core \
	#I_MPI_PIN_DOMAIN=[1,4] \
	#I_MPI_PIN_DOMAIN=1 I_MPI_PIN_CELL=unit \
	I_MPI_PIN_DOMAIN=auto I_MPI_PIN_CELL=unit I_MPI_PIN_ORDER=scatter \
	mpirun -n $(($clients_per_node * $n_nodes)) \
		-ppn $clients_per_node $mpi_params -genv LD_LIBRARY_PATH=/home/daos-user/local/hdf5/lib \
		$ior_build_dir/bin/ior \
		-t ${osize%MiB*}m -b ${osize%MiB*}m $rep_params \
		$api_param $rw_params \
		$ior_params $unique_param $keep_param -d $sleep \
		-E -C -e -v -v -v
		# ior segments:
		#-t ${osize%MiB*}m -b ${osize%MiB*}m $rep_params \
		# standard bw:
		#-t 1m -b 8g \
		# standard thr:
		#-t 4k -b 1g \
		# standard latency:
		#-t 4k -b 100m -z \

	for node in "${nodelist[@]}" ; do
		[[ "$node" == "$SLURMD_NODENAME" ]] && continue
		code=1
		while [ "$code" -ne 0 ] ; do
			echo "SENDING MESSAGE from $SLURMD_NODENAME to $node"
			echo "IOR build and launch on $SLURMD_NODENAME ended" | ncat $node 12345
			code=$?
			[ "$code" -ne 0 ] && sleep 2
		done
	done

else

	echo "WAITING FOR MESSAGE from $SLURMD_NODENAME"
	ncat -l -p 12345 | bash -c 'read MESSAGE; echo "${SLURMD_NODENAME}": $MESSAGE'

fi
