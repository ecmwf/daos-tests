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

cd $HOME/daos-tests/google/daos
test_name=patternA
#servers="sixteen_server"
servers="dual_server"
rep_modes=( "segment" )
osizes=("1MiB")
#ocs=("RP_2GX" "EC_2P1GX")
#ocs=("EC_2P1GX" "RP_2GX")
#ocs=("SX" "S1")
ocs=("SX")
#C=(16 12 8 4 2 1)
#C=(1 2 4 8 12)
#C=(1 2 4 8)
#C=(1 8 16 32)
#C=(48 32 16 8 1)
#C=(1 8 16 32)
#C=(32 16 8 1)
#C=(32)
C=(4)
REP=1
WR=10000
#apis=(DFUSE_IL DFUSE)
#apis=(DAOS HDF5 HDF5_DFUSE)
#apis=(DAOS DFS DFUSE DFUSE_IL HDF5 HDF5_DFUSE)
#apis=(DAOS DFS DFUSE DFUSE_IL)
#apis=(HDF5 HDF5_DFUSE)
#apis=(DFUSE_IL)
apis=(DAOS)
#apis=(DFS DFUSE DFUSE_IL HDF5 HDF5_DFUSE)
#DAOS DFS_OLD DFS DFUSE DFUSE_IL MPIIO MPIIO_DFUSE HDF5 HDF5_DFUSE
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
[[ "$api" == "DFS_OLD" ]] && posix_cont=true
[[ "$api" == "DFS" ]] && posix_cont=true
[[ "$api" == "DFUSE" ]] && posix_cont=true
[[ "$api" == "DFUSE_IL" ]] && posix_cont=true
[[ "$api" == "MPIIO_DFUSE" ]] && posix_cont=true
[[ "$api" == "HDF5_DFUSE" ]] && posix_cont=true
create_directory=false
for osize in "${osizes[@]}" ; do
for oc in "${ocs[@]}" ; do
ocname=$oc
[[ "$posix_cont" == "true" ]] && cont_oclass=$ocname
for c in "${C[@]}" ; do
#[ $c -eq 1 ] && N=(1 4 12 24 36 48 72 96 144 192)
#[ $c -eq 1 ] && N=(4 8 16)
#[ $c -eq 1 ] && N=(4 8 16)
#[ $c -eq 1 ] && N=(1)
[ $c -eq 1 ] && N=(1 4 8 12 16 24 32)
#[ $c -eq 1 ] && N=(1)
#[ $c -eq 2 ] && N=(1 4 12 18 24 36 48 72 96 144)
[ $c -eq 2 ] && N=(16)
#[ $c -eq 2 ] && N=(1 4 8 12 16 24 32)
#[ $c -eq 2 ] && N=(12 16 24 32)
#[ $c -eq 4 ] && N=(1 4 6 9 12 18 24 36 48 72)
#[ $c -eq 4 ] && N=(1 4 8 12 16 24 32)
#[ $c -eq 4 ] && N=(1 4 32)
[ $c -eq 4 ] && N=(32)
[ $c -eq 6 ] && N=(8 16 32)
#[ $c -eq 8 ] && N=(1 3 4 6 9 12 18 24 36 48)
#[ $c -eq 8 ] && N=(8 16 32)
[ $c -eq 8 ] && N=(1 4 8 12 16 24 32)
#[ $c -eq 8 ] && N=(32)
#[ $c -eq 10 ] && N=(1 3 4 6 9 12 18 24 36 48)
#[ $c -eq 12 ] && N=(1 3 4 6 9 12 18 24 36 48)
[ $c -eq 12 ] && N=(1 4 8 12 16 24 32)
#[ $c -eq 12 ] && N=(32)
[ $c -eq 14 ] && N=(1 3 4 6 9 12 18 24 36 48)
#[ $c -eq 16 ] && N=(1 3 4 6 9 12 18 24 36 48)
[ $c -eq 16 ] && N=(1 4 8 12 16 24 32)
#[ $c -eq 16 ] && N=(16 32)
#[ $c -eq 16 ] && N=(16)
[ $c -eq 18 ] && N=(1 3 4 6 9 12 18 24 36 48)
[ $c -eq 20 ] && N=(1 3 4 6 9 12 18 24 36 48)
#[ $c -eq 32 ] && N=(1 4 8 12 16 24 32)
[ $c -eq 32 ] && N=(24)
#[ $c -eq 48 ] && N=(16 32)
[ $c -eq 48 ] && N=(1 4 8 12 16 24 32)
#[ $c -eq 48 ] && N=(4)
#[ $c -eq 48 ] && N=(12 16)
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

    out=$(./ior/submitter.sh $c ior $api tcp $n $WR read $rep_mode \
        true true false $sleep $oc $osize $pool_id $cont_id)
    echo "$out"
    jid=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    while squeue | grep -q -e "^ *$jid .* ${USER::8} " ; do sleep 5 && echo "Sleeping..."; done

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
