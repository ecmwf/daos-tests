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

# USAGE: ./field_io/test_wrapper.sh <DAOS_TEST_SCRIPT_NAME> [options] <SCRIPT_ARGS>

start=`date +%s`

echo "Script launch time: $(date)"

test_name=$1
shift

fabric_provider=tcp
dummy_daos=OFF
simplified=OFF
simplified_kvs=OFF
oc_main_kv=OC_SX
oc_index_kv=OC_S2
oc_store_array=OC_S1

dummy_daos_dfuse=false
dummy_daos_ioil=false
pool_id=
cont_id=

OTHER=()
while [[ $# -gt 0 ]] ; do
key="$1"
case $key in
    -h|--help)
    echo -e "\
Usage:\n\n\
test_wrapper.sh DAOS_TEST_SCRIPT_NAME [options] SCRIPT_ARGS\n\n\
DAOS_TEST_SCRIPT_NAME: filename of the script to be submitted\n\n\
SCRIPT_ARGS: arguments to be forwarded to the DAOS test script in the first positional argument\n\n\
Available options:\n\n\
-PRV|--provider <provider>\n\nOFI fabric provider to use.\nofi+tcp by default.\n\n\
--simple|--simplified\n\nFlag to enable use of a simplified version of the field IO functions (single \
container with field data arrays stored directly, with hashed field key as oid).\n\n\
--simple-kvs|--simplified-kvs\n\nFlag to enable use of a simplified version of the field IO functions (single \
container with a main KV and an indexing KV and all field data arrays).\n\n\
--ocm|--oc-main-kv <OC_SPEC>\n\nspecify a DAOS object class to be used for the top-level KV objects.\n\
SX by default.\n\n\
--oci|--oc-index-kv <OC_SPEC>\n\nspecify a DAOS object class to be used for the index KV objects.\n\
SX by default.\n\n\
--ocs|--oc-store-array <OC_SPEC>\n\nspecify a DAOS object class to be used for the store array objects.\n\
S1 by default.\n\n\
--dummy\n\nFlag to enable use of dummy DAOS.\n\n\
-h|--help\n\nshow this menu\
"
    exit 0
    ;;
    -PRV|--provider)
    fabric_provider="$2"
    shift
    shift
    ;;
    --simple|--simplified)
    simplified=ON
    shift
    ;;
    --simple-kvs|--simplified-kvs)
    simplified_kvs=ON
    shift
    ;;
    --ocm|--oc-main-kv)
    oc_main_kv="$2"
    shift
    shift
    ;;
    --oci|--oc-index-kv)
    oc_index_kv="$2"
    shift
    shift
    ;;
    --ocs|--oc-store-array)
    oc_store_array="$2"
    shift
    shift
    ;;
    --dummy)
    dummy_daos=ON
    shift
    ;;
    --dfuse)
    dummy_daos_dfuse=true
    shift
    ;;
    --ioil)
    dummy_daos_ioil=true
    shift
    ;;
    -P|--pool)
    pool_id="$2"
    shift
    shift
    ;;
    -C|--container)
    cont_id="$2"
    shift
    shift
    ;;
    *)
    OTHER+=( "$1" )
    shift
    ;;
esac
done
set -- "${OTHER[@]}"

forward_args=("${OTHER[@]}")

profiling=OFF
test_src_dir=$HOME/daos-tests
build_root=$test_src_dir/src/field_io/build
field_io_shared_dir=$build_root/dummy_daos_${dummy_daos}_prof_${profiling}_simplified_${simplified}_simplified_kvs_${simplified_kvs}_oc_main_kv_${oc_main_kv}_oc_index_kv_${oc_index_kv}_oc_store_array_${oc_store_array}
ecbuild_path=$HOME/git/ecbuild

uuid_root=/usr
daos_root=/usr

fdb_src_dir=$HOME/fdb5_dummy
fdb_build_dir=$HOME/local/fdb5_dummy

dfuse_path=/tmp/daos_store
dummy_pool_id="00000000-0000-0000-0000-000000000000"
dummy_cont_id="00000000-0000-0000-0000-000000000001"

export I_MPI_OFI_LIBRARY_INTERNAL=0
source /opt/intel/setvars.sh

if [ "$SLURM_NODEID" -eq 0 ] ; then

	# Compile fdb5 with dummy DAOS

	if [[ "$dummy_daos" == "ON" ]] ; then
	
            if [ ! -d "${fdb_build_dir}" ] ; then

                # Compile fdb5

                status=succeeded

                git_dir=/tmp/git

                source_dir=${git_dir}/fdb-bundle
		if [ ! -d $source_dir ] ; then
                    mkdir -p $source_dir
                    cd $source_dir
                    git clone ssh://git@git.ecmwf.int/~manm/fdb-daos.git .
                fi

                if [ ! -d $git_dir/ecbuild ] ; then
                    git clone https://github.com/ecmwf/ecbuild.git ${git_dir}/ecbuild
                fi

                build_dir=/tmp/build
                mkdir -p $build_dir
                cd $build_dir

		daos_root=
                export UUID_ROOT=${uuid_root}
                export DAOS_ROOT=${daos_root}

                cmake $source_dir \
                    	-DENABLE_LUSTRE=OFF \
                    	-DENABLE_DAOSFDB=ON -DENABLE_DAOS_ADMIN=OFF \
                    	-DENABLE_DUMMY_DAOS=ON \
                    	-DENABLE_MEMFS=ON -DENABLE_AEC=OFF

                cmake --build .

                [ $? -ne 0 ] && status=failed
                
                rm -rf ${fdb_build_dir}
                cmake --install . --prefix ${fdb_build_dir}

                [ $? -ne 0 ] && status=failed

                [ ! -d $HOME/git/ecbuild ] && \
                	mkdir -p $HOME/git && \
		        cp -r ${git_dir}/ecbuild $HOME/git/
                	
            fi

            export FDB5_ROOT="$fdb_build_dir"

        fi

	# Compile daos rw binaries

	if [ ! -d $field_io_shared_dir ] ; then

		if [ ! -d $ecbuild_path ] ; then
			mkdir -p $ecbuild_path
			git clone https://github.com/ecmwf/ecbuild.git $ecbuild_path
		fi		
		export PATH="${ecbuild_path}/bin:$PATH"

		mkdir -p $field_io_shared_dir
		cd $field_io_shared_dir
		export DAOS_ROOT="$daos_root"
		export UUID_ROOT="$uuid_root"
		export FDB5_ROOT="$fdb_build_dir"
		ecbuild $test_src_dir/src/field_io \
			-DENABLE_PROFILING="$profiling" \
			-DENABLE_SIMPLIFIED="$simplified" \
			-DENABLE_SIMPLIFIED_KVS="$simplified_kvs" \
			-DENABLE_DUMMY_DAOS="$dummy_daos" \
			-DDAOS_FIELD_IO_OC_MAIN_KV="$oc_main_kv" \
			-DDAOS_FIELD_IO_OC_INDEX_KV="$oc_index_kv" \
			-DDAOS_FIELD_IO_OC_STORE_ARRAY="$oc_store_array"
		cmake --build .

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

	for node in "${nodelist[@]}" ; do
		[[ "$node" == "$SLURMD_NODENAME" ]] && continue
		code=1
		while [ "$code" -ne 0 ] ; do
			echo "SENDING MESSAGE from $SLURMD_NODENAME to $node"
			echo "field_io build on $SLURMD_NODENAME ended" | ncat $node 12345
			code=$?
			[ "$code" -ne 0 ] && sleep 2
		done
	done

else

	echo "WAITING FOR MESSAGE from $SLURMD_NODENAME"
	ncat -l -p 12345 | bash -c 'read MESSAGE; echo "${SLURMD_NODENAME}": $MESSAGE'

fi

export PATH="$field_io_shared_dir/bin:$PATH"

if [[ "$dummy_daos" == "ON" ]] && [[ "$dummy_daos_dfuse" == "true" ]] ; then

	mkdir -p $dfuse_path

	dfuse -m $dfuse_path --pool $pool_id --container $cont_id \
		--disable-caching --thread-count=24 --eq-count=12

	export DUMMY_DAOS_DATA_ROOT=${dfuse_path}
	
	mkdir -p ${dfuse_path}/${dummy_pool_id}/${dummy_cont_id}
	ln -s ${dfuse_path}/${dummy_pool_id}/${dummy_cont_id} ${dfuse_path}/${dummy_pool_id}/__dummy_daos_uuid_${dummy_cont_id}

fi


cd $test_src_dir/google/daos

if [[ "$test_name" == "test_field_io" ]] ; then
	forward_args+=( \
		"--num-nodes" "$SLURM_JOB_NUM_NODES" \
		"--node-id" "$SLURM_NODEID" \
	)
	if [[ "$dummy_daos" == "ON" ]] && [[ "$dummy_daos_dfuse" == "true" ]] ; then
		forward_args+=( \
			"--pool" "$dummy_pool_id" \
			"--container" "$dummy_cont_id" \
		)
	else
		forward_args+=( \
			"--pool" "$pool_id" \
			"--container" "$cont_id" \
		)
	fi
fi

end=`date +%s`

setup_time=$((end-start))

start=`date +%s`
echo "./field_io/${test_name}.sh ${forward_args[@]}"
[[ "$dummy_daos_dfuse" == "true" ]] && [[ "$dummy_daos_ioil" == "true" ]] && echo "WARNING: libioil will override some symbols in libdummy_daos!" && export LD_PRELOAD=/usr/lib64/libioil.so
./field_io/${test_name}.sh "${forward_args[@]}"
end=`date +%s`

test_time=$((end-start))

wc_time=$((setup_time+test_time))




if [[ "$dummy_daos" == "ON" ]] && [[ "$dummy_daos_dfuse" == "true" ]] ; then
	sudo umount $dfuse_path
fi




echo "Profiling node $SLURM_NODEID - setup wc time: $setup_time"
echo "Profiling node $SLURM_NODEID - $test_name total wc time: $test_time"
echo "Profiling node $SLURM_NODEID - total wc time: $wc_time"
