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

# --- PARAMETERS ---

# number of nodes DAOS has been deployed on
servers="sixteen_server"

# number of client nodes to run the becnhmark on
C=(32 16 8 1)

# Note: also review values for N below to configure
# number of processes per clietn node

# number of I/O operations per process
WR=10000

# size of the fields to be written/read
osizes=("1MiB")

# object classes to test for the KVs and Arrays
ocvecs=( "OC_S1 OC_S1" )
ocvecs=( "OC_SX OC_SX OC_S1" )

# test repetitions
REP=3

# ------------------

cd $HOME/daos-tests/google/daos
test_name=patternA
simplified=( "--simple-kvs" )
posix_cont="false"
dummy_daos="false"
dummy_daos_dfuse="false"
dummy_daos_ioil="false"
sleep=0
source pool_helpers.sh
for s in "${simplified[@]}" ; do
dummy_daos_arg=()
tname=${test_name}
if [[ "$dummy_daos" == "true" ]] ; then
    tname=${tname}_dummy
    dummy_daos_arg=("--dummy")
    if [[ "$dummy_daos_dfuse" == "true" ]] ; then
        tname+="_dfuse"
	posix_cont="true"
	dummy_daos_arg+=("--dfuse")
	[[ "$dummy_daos_ioil" == "true" ]] && tname+="_il" && dummy_daos_arg+=("--ioil")
    fi
fi
[[ "$s" == "--simple" ]] && tname=${tname}_simple
[[ "$s" == "--simple-kvs" ]] && tname=${tname}_simple_kvs
[ $sleep -gt 0 ] && tname=${tname}_sleep
[ $sleep -gt 1 ] && tname=${tname}${sleep}
for osize in "${osizes[@]}" ; do
for ocvec in "${ocvecs[@]}" ; do
ocname=$(echo ${ocvec} | tr ' ' '_')
ocvec=($(echo "$ocvec"))
for c in "${C[@]}" ; do
[ $c -eq 1 ] && N=(1 4 8 12 16 24 32)
[ $c -eq 8 ] && N=(1 4 8 12 16 24 32)
[ $c -eq 16 ] && N=(1 4 8 12 16 24 32)
[ $c -eq 32 ] && N=(1 4 8 12 16 24 32)
for n in "${N[@]}" ; do
for r in `seq 1 $REP` ; do
    echo "### Pattern A $s, ${ocvec[@]}, ${osize}, C=$c, N=$n, rep=$r ###"

    nnodes=$c
    nodes_ready=0
    while [ $nodes_ready -eq 0 ] ; do
        echo "Provisioning client nodes..."
        out=$(timeout 120 srun -N $nnodes hostname)
        res=$(echo "${out}" | wc -l)
        out=$(squeue | grep ${USER::8} | wc -l)
        while [ $out -gt 0 ] ; do
          squeue | grep ${USER::8} | awk '{print $1}' | xargs scancel
          echo "Waiting for jobs to terminate..." && sleep 10
          out=$(squeue | grep ${USER::8} | wc -l)
        done
        if [ $res -eq $nnodes ] ; then
          nodes_ready=1
        else
            sleep 3
            out=1
            while [ $out -ne 0 ] ; do
              echo "Waiting for all nodes to be idle~ or idle..." && sleep 90
              out=$(sinfo -N | tail -n+2 | grep -v -e 'idle~' -e 'idle ' | wc -l)
            done
        fi
    done
    echo "Client nodes provisioned"

    sleep 5

    out=$(create_pool_cont $posix_cont $dummy_daos $servers field_io ${ocvec[2]#*_})
    code=$?
    [ $code -ne 0 ] && echo "create_pool_cont failed" && echo "${out}" && return
    pool_id=$(echo "$out" | grep "POOL: " | awk '{print $2}')
    cont_id=$(echo "$out" | grep "CONT: " | awk '{print $2}')
    echo "Pool is: $pool_id"
    echo "Cont is: $cont_id"

    # dummy daos only supports S1. If using SX and running on posix, it will be forced to S1.
    # If using SX and running on dfuse, the posix container will have been created with SX.
    [[ "$dummy_daos" == "true" ]] && ocvec=("OC_S1" "OC_S1" "OC_S1")

    span_length=10
    io_start_barrier=$(( $(date +%s) + ${span_length} + 15 ))
    out=$(./field_io/submitter.sh $c test_field_io -PRV tcp $s --osize ${osize} \
        --ocm ${ocvec[0]} --oci ${ocvec[1]} --ocs ${ocvec[2]} \
        $n $WR 0 -P $pool_id -C $cont_id --unique --n-to-write $WR \
        --sleep $sleep -L ${span_length} -B $io_start_barrier "${dummy_daos_arg[@]}")
    echo "$out"
    jid=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    while squeue | grep -q -e "^ *$jid .* ${USER::8} " ; do sleep 5 && echo "Sleeping..."; done

    nnodes=$c
    nodes_ready=0
    while [ $nodes_ready -eq 0 ] ; do
        echo "Provisioning client nodes..."
        out=$(timeout 120 srun -N $nnodes hostname)
        res=$(echo "${out}" | wc -l)
        out=$(squeue | grep ${USER::8} | wc -l)
        while [ $out -gt 0 ] ; do
          squeue | grep ${USER::8} | awk '{print $1}' | xargs scancel
          echo "Waiting for jobs to terminate..." && sleep 10
          out=$(squeue | grep ${USER::8} | wc -l)
        done
        if [ $res -eq $nnodes ] ; then
          nodes_ready=1
        else
            sleep 3
            out=1
            while [ $out -ne 0 ] ; do
              echo "Waiting for all nodes to be idle~ or idle..." && sleep 90
              out=$(sinfo -N | tail -n+2 | grep -v -e 'idle~' -e 'idle ' | wc -l)
            done
        fi
    done
    echo "Client nodes provisioned"

    sleep 5

    io_start_barrier=$(( $(date +%s) + ${span_length} + 15 ))
    out=$(./field_io/submitter.sh $c test_field_io -PRV tcp $s --osize ${osize} \
        --ocm ${ocvec[0]} --oci ${ocvec[1]} --ocs ${ocvec[2]} \
        $n 0 $WR -P $pool_id -C $cont_id --unique --n-to-read $WR \
        --sleep $sleep -L ${span_length} -B $io_start_barrier "${dummy_daos_arg[@]}")
    echo "$out"
    jid=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    while squeue | grep -q -e "^ *$jid .* ${USER::8} " ; do sleep 5 && echo "Sleeping..."; done

    out=$(destroy_pool_cont $dummy_daos $servers)
    code=$?
    [ $code -ne 0 ] && echo "destroy_pool_cont failed for N=$n" && echo "${out}" && return
done
done
done
res_dir=runs/${servers}/field_io/${tname}/${ocname}/${osize}
mkdir -p $res_dir
mv runs/daos_* ${res_dir}/
done
done
done
