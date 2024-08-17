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

# USAGE: ./field_io/test_wrapper.sh <FDB_HAMMER_SCRIPT_NAME> [options] <SCRIPT_ARGS>

start=`date +%s`

echo "Script launch time: $(date)"

test_name=$1
shift

num_nodes=$SLURM_JOB_NUM_NODES
fabric_provider=tcp
oc_catalogue_kvs=OC_SX
oc_store_arrays=OC_S1

OTHER=()
while [[ $# -gt 0 ]] ; do
key="$1"
case $key in
    -h|--help)
    echo -e "\
Usage:\n\n\
test_wrapper.sh FDB_HAMMER_SCRIPT_NAME [options] SCRIPT_ARGS\n\n\
FDB_HAMMER_SCRIPT_NAME: filename of the script to be submitted\n\n\
SCRIPT_ARGS: arguments to be forwarded to the FDB Hammer test script in the first positional argument\n\n\
Available options:\n\n\
--num-nodes <n>\n\nNumber of client nodes that are assumed to be running this script in parallel in index calculations.\nSLURM_JOB_NUM_NODES by default.\n\n\
-PRV|--provider <provider>\n\nOFI fabric provider to use.\nofi+tcp;ofi_rxm by default.\n\n\
--ock|--oc-catalogue-kvs <OC_SPEC>\n\nspecify a DAOS object class to be used for the FDB Catalogue KV objects.\n\
SX by default.\n\n\
--oca|--oc-store-arrays <OC_SPEC>\n\nspecify a DAOS object class to be used for the FDB Store array objects.\n\
S1 by default.\n\n\
--daos\n\nFlag to enable use of FDB DAOS back-end.\n\n\
--dummy\n\nFlag to enable use of dummy DAOS.\n\n\
-h|--help\n\nshow this menu\
"
    exit 0
    ;;
    --num-nodes)
    num_nodes="$2"
    shift
    shift
    ;;
    -PRV|--provider)
    fabric_provider="$2"
    shift
    shift
    ;;
    --ock|--oc-catalogue-kvs)
    oc_catalogue_kvs="$2"
    shift
    shift
    ;;
    --oca|--oc-store-arrays)
    oc_store_arrays="$2"
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

test_src_dir=$HOME/daos-tests

fdb_src_dir=$HOME/fdb5_posix
fdb_build_dir=$HOME/local/fdb5_posix

mount_dir=/newlust
ready=0
while [ $ready -eq 0 ] ; do
  available=$(getent ahostsv4 mystore-manager | wc -l)
  [ $available -eq 0 ] && echo "Store manager not available." && exit 1
  mounted=$(mount -l | grep "${mount_dir} on ${mount_dir}" | wc -l)
  if [ $mounted -ne 0 ] ; then
    sudo umount -l ${mount_dir}
    [ $? -ne 0 ] && echo "Umount failed. Waiting..." && sleep 10 && continue
  fi
  mgsip="$(getent ahostsv4 mystore-manager | grep RAW | awk '{print $1}')@tcp"
  sudo mkdir -p ${mount_dir}
  sudo chmod 777 ${mount_dir}
  sudo timeout 3 mount -t lustre ${mgsip}:${mount_dir} ${mount_dir}
  [ $? -ne 0 ] && echo "Mount failed or took too long." && exit 1
  sudo chmod 777 ${mount_dir}
  ready=1
done

uuid_root=/usr
daos_root=/usr

source /opt/intel/setvars.sh














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


















if [ "$SLURM_NODEID" -eq 0 ] ; then

    if [ ! -d "${fdb_build_dir}" ] ; then

	# Compile fdb5

	status=succeeded

	git_dir=/tmp/git

	source_dir=${git_dir}/fdb-bundle
	mkdir -p $source_dir
	cd $source_dir
	git clone ssh://git@git.ecmwf.int/~manm/fdb-daos.git .
        # make sure CMakeLists points to eckit/develop and fdb/manm_fdbhamer_prof

	git clone https://github.com/ecmwf/ecbuild.git ${git_dir}/ecbuild

	build_dir=/tmp/build
	mkdir -p $build_dir
	cd $build_dir

        sudo ln -s /usr/lib64/liblustreapi.so.1 /usr/lib64/liblustreapi.so

        cmake $source_dir \
                -DENABLE_LUSTRE=ON \
                -DENABLE_RADOS=OFF -DENABLE_RADOSFDB=OFF \
                -DENABLE_DAOSFDB=OFF -DENABLE_DAOS_ADMIN=OFF \
                -DENABLE_DUMMY_DAOS=OFF \
                -DENABLE_MEMFS=ON -DENABLE_AEC=OFF
        # check all "uncomment for" in fdb source

	cmake --build .

	#[ $? -ne 0 ] && echo "${out}" >&2 && status=failed
	[ $? -ne 0 ] && status=failed
	
	#ctest -j 12 -R daos

	rm -rf ${fdb_build_dir}
	cmake --install . --prefix ${fdb_build_dir}

	#[ $? -ne 0 ] && echo "${out}" >&2 && status=failed
        [ $? -ne 0 ] && status=failed

	#rm -rf $HOME/fdb5_build
	#mkdir -p $HOME/fdb5_build
	#cp -r ${build_dir}/* $HOME/fdb5_build/

	#rm -rf ${fdb_src_dir}
	#cp -r ${source_dir} ${fdb_src_dir}

	[ ! -d $HOME/git/ecbuild ] && \
		mkdir -p $HOME/git && \
		cp -r ${git_dir}/ecbuild $HOME/git/

    fi

    cd $fdb_build_dir

	for node in "${nodelist[@]}" ; do
		[[ "$node" == "$SLURMD_NODENAME" ]] && continue
		code=1
		while [ "$code" -ne 0 ] ; do
			echo "SENDING MESSAGE from $SLURMD_NODENAME to $node"
			echo "fdb5 build on $SLURMD_NODENAME ${status}" | ncat $node 12345
			code=$?
			[ "$code" -ne 0 ] && sleep 2
		done
	done
    [[ "${status}" == "failed" ]] && exit 1

else

	echo "WAITING FOR MESSAGE from $SLURMD_NODENAME"
	m=$(ncat -l -p 12345 | bash -c 'read MESSAGE; echo "${SLURMD_NODENAME}": $MESSAGE')
    [[ "${m}" == *"failed"* ]] && exit 1

fi

export PATH="$fdb_build_dir/bin:$PATH"

cd $test_src_dir/google/lustre

[[ "$test_name" == "test_fdb_hammer" ]] && forward_args+=( "--num-nodes" "$num_nodes" "--node-id" "$SLURM_NODEID" )
forward_args+=( "--posix" )

end=`date +%s`

setup_time=$((end-start))

start=`date +%s`
echo "./fdb_hammer/${test_name}.sh ${forward_args[@]}"
./fdb_hammer/${test_name}.sh "${forward_args[@]}"
end=`date +%s`

test_time=$((end-start))

wc_time=$((setup_time+test_time))




echo "Profiling node $SLURM_NODEID - setup wc time: $setup_time"
echo "Profiling node $SLURM_NODEID - $test_name total wc time: $test_time"
echo "Profiling node $SLURM_NODEID - total wc time: $wc_time"
