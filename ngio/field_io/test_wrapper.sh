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
simplified=OFF
simplified_kvs=OFF
oc_main_kv=OC_SX
oc_index_kv=OC_S2
oc_store_array=OC_S1

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
field_io_shared_dir=$test_src_dir/src/field_io/build/prof_${profiling}_simplified_${simplified}_simplified_kvs_${simplified_kvs}_oc_main_kv_${oc_main_kv}_oc_index_kv_${oc_index_kv}_oc_store_array_${oc_store_array}
ecbuild_path=$HOME/ecbuild/bin
daos_root=/usr
uuid_root=$HOME/install

if [ "$SLURM_NODEID" -eq 0 ] ; then

	# Compile daos rw binaries

	if [ ! -d $field_io_shared_dir ] ; then

		mkdir -p $field_io_shared_dir
		cd $field_io_shared_dir
		module load cmake
		export PATH="$ecbuild_path:$PATH"
		export DAOS_ROOT="$daos_root"
		export UUID_ROOT="$uuid_root"
		ecbuild $test_src_dir/src/field_io \
			-DENABLE_PROFILING="$profiling" \
			-DENABLE_SIMPLIFIED="$simplified" \
			-DENABLE_SIMPLIFIED_KVS="$simplified_kvs" \
			-DDAOS_FIELD_IO_OC_MAIN_KV="$oc_main_kv" \
			-DDAOS_FIELD_IO_OC_INDEX_KV="$oc_index_kv" \
			-DDAOS_FIELD_IO_OC_STORE_ARRAY="$oc_store_array"
		cmake --build .

	fi

	nodelist=($(python - "$SLURM_NODELIST" <<EOF
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
        for j in range(int(limits[0]), int(limits[1]) + 1):
          print(parts[0] + "%02d" % (j,))
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

export LD_LIBRARY_PATH=/usr/lib64:$LD_LIBRARY_PATH

export PATH="$field_io_shared_dir/bin:$PATH"
export LD_LIBRARY_PATH="$field_io_shared_dir/lib:$LD_LIBRARY_PATH"

module load libfabric/latest
export LD_LIBRARY_PATH=/home/software/psm2/11.2.228/usr/lib64:/home/software/libfabric/latest/lib:$LD_LIBRARY_PATH

rm -rf /tmp/daos/log

mkdir -p /tmp/daos/log
mkdir -p /tmp/daos/run/daos_agent
chmod 0755 /tmp/daos/run/daos_agent

if [ "$fabric_provider" == "sockets" ] ; then
	export CRT_PHY_ADDR_STR="ofi+sockets"
	export FI_SOCKETS_MAX_CONN_RETRY=1
	export FI_SOCKETS_CONN_TIMEOUT=2000
elif [ "$fabric_provider" == "tcp" ] ; then
    #export FI_TCP_IFACE=ib0
    export FI_TCP_BIND_BEFORE_CONNECT=1
    export CRT_PHY_ADDR_STR="ofi+tcp;ofi_rxm"
    export FI_PROVIDER=tcp

	export FI_TCP_MAX_CONN_RETRY=1
	export FI_TCP_CONN_TIMEOUT=2000
elif [ "$fabric_provider" == "psm2" ] ; then
	export CRT_PHY_ADDR_STR="ofi+psm2"
else
	echo "Unsupported fabric provider $fabric_provider (test name $test_name)"
	exit 1
fi

export D_LOG_MASK=
export DD_SUBSYST=all
export DD_MASK=all
export DAOS_AGENT_DRPC_DIR=/tmp/daos/run/daos_agent/
export CRT_TIMEOUT=1000
export CRT_CREDIT_EP_CTX=0

daos_agent -o $test_src_dir/ngio/config/daos_agent.yaml -i &

sleep 5

cd $test_src_dir/ngio

[[ "$test_name" == "test_field_io" ]] && forward_args+=( "--node-id" "$SLURM_NODEID" )

end=`date +%s`

setup_time=$((end-start))

start=`date +%s`
echo "./field_io/${test_name}.sh ${forward_args[@]}"
./field_io/${test_name}.sh "${forward_args[@]}"
end=`date +%s`

test_time=$((end-start))

wc_time=$((setup_time+test_time))

pkill daos_agent

echo "Profiling node $SLURM_NODEID - setup wc time: $setup_time"
echo "Profiling node $SLURM_NODEID - $test_name total wc time: $test_time"
echo "Profiling node $SLURM_NODEID - total wc time: $wc_time"
