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
dfuse_path=/tmp/daos_store
api_param="-a $ior_api"

#export I_MPI_OFI_LIBRARY_INTERNAL=0
#export FI_PROVIDER=tcp
source /opt/intel/setvars.sh

if [[ "$ior_api" == "DAOS" ]] ; then

	ior_params="-o file_name --daos.pool $pool --daos.cont $cont --daos.oclass $oc"
	ior_src+="_daos"

elif [[ "$ior_api" == "DFS" ]] || [[ "$ior_api" == "DFS_OLD" ]] ; then

        dir_oclass=$oc
        [[ $oc == "EC_"* ]] && dir_oclass="RP_2G${oc#*G}"
	ior_params="-o /file_name --dfs.pool $pool --dfs.cont $cont --dfs.oclass $oc --dfs.dir_oclass $dir_oclass"
	[[ "$ior_api" == "DFS_OLD" ]] && ior_src+="_daos" && api_param="-a DFS"

elif [[ "$ior_api" == "DFUSE" ]] || [[ "$ior_api" == "DFUSE_IL" ]] || \
	[[ "$ior_api" == "MPIIO_DFUSE" ]] || [[ "$ior_api" == "HDF5_DFUSE" ]] ; then

	ior_params="-o $dfuse_path/test"
	[[ "$ior_api" == "DFUSE" ]] || [[ "$ior_api" == "DFUSE_IL" ]] && \
		ior_params+=" -O useO_DIRECT=1" && \
		api_param=
	mpi_params="-genv LD_PRELOAD="
	#[[ "$ior_api" == "DFUSE_IL" ]] || [[ "$ior_api" == "HDF5_DFUSE" ]] && mpi_params="-genv LD_PRELOAD=/usr/lib64/libioil.so"
	[[ "$ior_api" == "DFUSE_IL" ]] && mpi_params="-genv LD_PRELOAD=/usr/lib64/libioil.so"

	mkdir -p $dfuse_path
	dfuse -m $dfuse_path --pool $pool --container $cont \
  		--disable-caching --thread-count=24 --eq-count=12

	#ls -l $dfuse_path
	#[ "$n_nodes" -gt 16 ] && sleep 10

	if [[ "$ior_api" == "MPIIO_DFUSE" ]] ; then

		api_param="-a MPIIO"
		with_mpiio="--with-mpiio=yes"

	elif [[ "$ior_api" == "HDF5_DFUSE" ]] ; then

		api_param="-a HDF5"
		with_mpiio="--with-hdf5"

	fi

elif [[ "$ior_api" == "MPIIO" ]] ; then

	echo "MPIIO backend not implemented" && exit 1

	ior_params="-o daos://test"
	with_mpiio="--with-mpiio=yes"
	export DAOS_POOL=$pool
	export DAOS_CONT=$cont
	export IOR_HINT__MPI__romio_daos_obj_class=$oc
	export DAOS_BYPASS_DUNS=1
	export I_MPI_OFI_LIBRARY_INTERNAL=0

elif [[ "$ior_api" == "HDF5" ]] ; then

	ior_params="-o test"
	with_mpiio="--with-hdf5"
	export HDF5_VOL_CONNECTOR="daos"
	export HDF5_PLUGIN_PATH="$HOME/local/vol-daos/lib"
	export DAOS_POOL="$pool"
	#export DAOS_SYS="daos"
	export HDF5_DAOS_BYPASS_DUNS=1
	export HDF5_DAOS_OBJ_CLASS=$oc
	#export I_MPI_OFI_LIBRARY_INTERNAL=0

else
	echo "Unsupported IOR API" && exit 1
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

    ior_build_dir=$ior_shared_dir/${ior_api}

    if [ ! -d $ior_build_dir ] ; then
    if [ ! -d $ior_src ] ; then
        mkdir $ior_src
        cd $ior_src
        git clone https://github.com/hpc/ior.git .
        [[ "$ior_api" == "DAOS" ]] || [[ "$ior_api" == "DFS_OLD" ]] && git checkout 3.3.0rc1
    fi
    cd $ior_src
    if [[ "$ior_api" == "DAOS" ]] || [[ "$ior_api" == "DFS_OLD" ]] ; then

            # these modifications are intended for IOR 3.3.0rc1 to work with DAOS 1.2
            grep -r -l "daos_pool_connect" * | xargs sed -i -e 's/svcl, //g'
            grep -r -l "daos_pool_connect" * | xargs sed -i -e 's/o.svcl == NULL || //g'
            grep -r -l "daos_pool_connect" * | xargs sed -i -e 's/.*svcl.*//g'

            # these modifications are intended for IOR 3.3.0rc1 and 3.3.0 to work with DAOS 2.0
            grep -r -l "daos_array_generate_id" * | xargs sed -i -e 's/daos_array_generate_id(.*/daos_array_generate_oid(coh, oid, true, objectClass, 0, 0);/g'

            # these modifications are intended for IOR 3.3.0rc1 and 3.3.0 to work with DAOS 2.3.108-tb
            # for DAOS API:
            grep -r -l "daos_cont_open" * | xargs sed -i -e 's/daos_cont_open(poh, uuid/daos_cont_open(poh, o.cont/g'
            grep -r -l "daos_cont_create" * | xargs sed -i -e 's/daos_cont_create(poh, uuid, NULL/daos_cont_create_with_label(poh, o.cont, NULL, \&uuid/g'
            grep -r -l "daos_pool_connect" * | xargs sed -i -e 's/daos_pool_connect(uuid/daos_pool_connect(o.pool/g'
            # for DFS API:
            grep -r -l "dfs_init;" * | xargs sed -i -e 's/dfs_init;/dfs_init_flag;/g'
            grep -r -l "dfs_init)" * | xargs sed -i -e 's/dfs_init)/dfs_init_flag)/g'
            grep -r -l "dfs_init " * | xargs sed -i -e 's/dfs_init /dfs_init_flag /g'
            grep -r -l "daos_cont_open" * | xargs sed -i -e 's/daos_cont_open(poh, co_uuid/daos_cont_open(poh, o.cont/g'
            grep -r -l "dfs_cont_create" * | xargs sed -i -e 's/dfs_cont_create(poh, co_uuid, NULL/dfs_cont_create_with_label(poh, o.cont, NULL, \&co_uuid/g'
            grep -r -l "daos_pool_connect" * | xargs sed -i -e 's/daos_pool_connect(pool_uuid/daos_pool_connect(o.pool/g'

            grep -r -l "dfs_init" * | xargs sed -i -e 's/dfs_init\t/dfs_init_flag\t/g'
            grep -r -l "uuid_parse(o.pool" * | xargs sed -i -e 's/rc = uuid_parse(o.pool, uuid);//g'

    fi
    make distclean
    ./bootstrap
    if [[ "$ior_api" == "DAOS" ]] || [[ "$ior_api" == "DFS_OLD" ]] ; then
            ./configure --with-cart=/usr --with-daos=/usr --prefix=$ior_build_dir
    elif [[ "$ior_api" == "HDF5" ]] || [[ "$ior_api" == "HDF5_DFUSE" ]] ; then
            ./configure $with_mpiio --with-cuda=no --with-daos=/usr --prefix=$ior_build_dir CFLAGS="-I /home/daos-user/local/hdf5/include" LDFLAGS="-L /home/daos-user/local/hdf5/lib"
    	#mpi_params+=" -genv LD_LIBRARY_PATH=/home/daos-user/local/hdf5/lib"
    else
            ./configure $with_mpiio --with-cuda=no --with-daos=/usr --prefix=$ior_build_dir
    fi
    make
    make install
    fi  #endif no build dir

fi  #endif node 0


if [ $SLURM_NODEID -eq 0 ] ; then

	rw_params=
	[[ "$write_or_read" == "write" ]] && rw_params="-w"
	[[ "$write_or_read" == "read" ]] && rw_params="-r"

	unique_rep_param=
	[[ "$unique_rep" == "true" ]] && unique_rep_param="-m"

	rep_params=
	[[ "$rep_mode" == "rep" ]] && rep_params="-s 1 -i $reps_per_client $unique_rep_param"
	[[ "$rep_mode" == "segment" ]] && rep_params="-s $reps_per_client"

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
		-ppn $clients_per_node $mpi_params \
		-genv LD_LIBRARY_PATH=/home/daos-user/local/hdf5/lib \
		-genv HDF5_DAOS_OBJ_CLASS $oc \
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

if [[ "$ior_api" == "DFUSE" ]] || [[ "$ior_api" == "DFUSE_IL" ]] || \
	[[ "$ior_api" == "MPIIO_DFUSE" ]] || [[ "$ior_api" == "HDF5_DFUSE" ]] ; then

	sudo umount $dfuse_path

fi
