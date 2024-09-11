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

# number of nodes Lustre has been deployed on
servers="sixteen_server"

# number of client nodes to run the becnhmark on
C=(32 16 8 1)

# Note: also review values for N below to configure
# number of processes per clietn node

# number of I/O operations per process
WR=10000

# size of the write/read operations
# (all going to a file per process)
osizes=("1MiB")

# test repetitions
REP=3

# ------------------
cd $HOME/daos-tests/google/lustre
test_name=patternA
rep_modes=( "segment" )
osizes=("1MiB")
ocs=("SX")
apis=(POSIX)
sleep=0
source pool_helpers.sh
for rep_mode in "${rep_modes[@]}" ; do
tname=${test_name}
[[ "$rep_mode" == "segment" ]] && tname=${test_name}_segment
[ $sleep -gt 0 ] && tname=${tname}_sleep
[ $sleep -gt 1 ] && tname=${tname}${sleep}
for api in "${apis[@]}" ; do
posix_cont=false
cont_oclass=
create_directory=false
[[ "$api" == "POSIX" ]] && create_directory=true
for osize in "${osizes[@]}" ; do
for oc in "${ocs[@]}" ; do
ocname=$oc
[[ "$posix_cont" == "true" ]] || [[ "$api" == "POSIX" ]] && cont_oclass=$ocname
for c in "${C[@]}" ; do
[ $c -eq 1 ] && N=(1 4 8 12 16 24 32)
[ $c -eq 8 ] && N=(1 4 8 12 16 24 32)
[ $c -eq 16 ] && N=(1 4 8 12 16 24 32)
[ $c -eq 32 ] && N=(1 4 8 12 16 24 32)
for n in "${N[@]}" ; do
for r in `seq 1 $REP` ; do

    echo "### IOR Pattern A ${rep_mode}, ${oc}, ${osize}, API=$api, C=$c, N=$n, rep=$r ###"

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

    out=$(create_pool_cont $posix_cont $create_directory $servers "ior" $cont_oclass)
    code=$?
    [ $code -ne 0 ] && echo "create_pool_cont failed" && echo "${out}" && return
    pool_id=$(echo "$out" | grep "POOL: " | awk '{print $2}')
    cont_id=$(echo "$out" | grep "CONT: " | awk '{print $2}')
    echo "Pool is: $pool_id"
    echo "Cont is: $cont_id"

    out=$(./ior/submitter.sh $c ior $api tcp $n $WR write $rep_mode \
        true true true $sleep $oc $osize $pool_id $cont_id)
    echo "$out"
    jid=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    next=0
    while squeue | grep -q -e "^ *$jid .* ${USER::8} " ; do
        sleep 5
        echo "Sleeping..."
        res=$(getent ahostsv4 mystore-manager | grep RAW | awk '{print $1}' | wc -l)
        [ $res -eq 0 ] && echo "Cancelling..." && scancel $jid && sleep 30 && next=1
    done
    [ $next -eq 1 ] && continue

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

    out=$(./ior/submitter.sh $c ior $api tcp $n $WR read $rep_mode \
        true true false $sleep $oc $osize $pool_id $cont_id)
    echo "$out"
    jid=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    next=0
    while squeue | grep -q -e "^ *$jid .* ${USER::8} " ; do
        sleep 5
        echo "Sleeping..."
        res=$(getent ahostsv4 mystore-manager | grep RAW | awk '{print $1}' | wc -l)
        [ $res -eq 0 ] && echo "Cancelling..." && scancel $jid && sleep 30 && next=1
    done
    [ $next -eq 1 ] && continue

    out=$(destroy_pool_cont $create_directory $servers ior)
    code=$?
    if [ $code -ne 0 ] ; then
        echo "Retrying destroy in 120s..."
        sleep 120
        out=$(destroy_pool_cont $create_directory $servers ior)
        code=$?
    fi
    [ $code -ne 0 ] && echo "destroy_pool_cont failed for N=$n" && echo "${out}" && return

done
done
done
res_dir=runs/${servers}/ior/${tname}/${ocname}/${osize}/${api}
mkdir -p $res_dir
mv runs/daos_* ${res_dir}/
done
done
done
done
