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

# number of nodes Ceph has been deployed on
servers="sixteen_server"

# number of client nodes to run the becnhmark on
C=(32 16 8 1)

# Note: also review values for N below to configure
# number of processes per clietn node

# number of I/O operations per process
WR=10000

# size of the fields to be written/read
osizes=("1MiB")

# test repetitions
REP=3

# ------------------

ready=0
while [ $ready -eq 0 ] ; do
  echo "Waiting for Ceph to be ready..."
  res=$(sudo timeout 3 ceph -s)
  [ $? -eq 0 ] && ready=1 && continue
  sleep 5
done

cd $HOME/daos-tests/google/ceph
test_name=patternA
ocvecs=( "OC_S1 OC_S1" )
posix_cont="false"
dummy_daos="false"
sleep=0
source pool_helpers.sh
tname=${test_name}
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

    echo "### Pattern A, ${ocvec[@]}, ${osize}, C=$c, N=$n, rep=$r ###"

    nnodes=$c
    nodes_ready=0
    while [ $nodes_ready -eq 0 ] ; do
       res=$(srun -N $nnodes hostname | wc -l)
       [ $res -eq $nnodes ] && nodes_ready=1 || sleep 10
    done

    sleep 5

    out=$(create_pool_cont $posix_cont $dummy_daos $servers fdb_hammer)
    code=$?
    [ $code -ne 0 ] && echo "create_pool_cont failed" && echo "${out}" && return
    pool=$(echo "$out" | grep "POOL: " | awk '{print $2}')
    cont_id=$(echo "$out" | grep "CONT: " | awk '{print $2}')
    echo "Pool is: $pool"
    echo "Cont is: $cont_id"

    sleep 5

    out=$(./fdb_hammer/submitter.sh $c test_fdb_hammer -PRV tcp \
        --osize ${osize} \
        --ock ${ocvec[0]} --oca ${ocvec[1]} --rados \
        $n $WR 0 -P $pool -C $cont_id \
	--nsteps 100 --nparams 10)
#        --nmembers= --ndatabases= --nlevels=
    echo "$out"
    jid=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    while squeue | grep -q -e "^ *$jid .* ${USER::8} " ; do sleep 5 && echo "Sleeping..."; done

    sleep 5

    ready=0
    service_ready=
    while [ $ready -eq 0 ] ; do
      echo "Waiting for Ceph to be ready..."
      status=$(sudo ceph -s)
      echo "${status}" | tr '\r\n' '_' | grep -q -e 'health: HEALTH_WARN_ *1 pool(s)' -e 'health: HEALTH_ERR_ *2 pool(s)' -e 'health: HEALTH_OK'
      service_ready=$?
      [ $service_ready -eq 0 ] && ready=1 && continue
      sleep 5
    done

    nnodes=$c
    nodes_ready=0
    while [ $nodes_ready -eq 0 ] ; do
       res=$(srun -N $nnodes hostname | wc -l)
       [ $res -eq $nnodes ] && nodes_ready=1 || sleep 10
    done

    sleep 5

    out=$(./fdb_hammer/submitter.sh $c test_fdb_hammer -PRV tcp \
        --osize ${osize} \
        --ock ${ocvec[0]} --oca ${ocvec[1]} --rados \
        $n 0 $WR -P $pool -C $cont_id \
	--nsteps 100 --nparams 10)
    echo "$out"
    jid=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    while squeue | grep -q -e "^ *$jid .* ${USER::8} " ; do sleep 5 && echo "Sleeping..."; done

    sleep 5

    out=$(destroy_pool_cont $dummy_daos $servers fdb_hammer)
    code=$?
    [ $code -ne 0 ] && echo "destroy_pool_cont failed for N=$n" && return

    sleep 10

done
done
done
res_dir=runs/${servers}/fdb_hammer/${tname}/${ocname}/${osize}
mkdir -p $res_dir
mv runs/fdb_hammer_* ${res_dir}/
done
done
