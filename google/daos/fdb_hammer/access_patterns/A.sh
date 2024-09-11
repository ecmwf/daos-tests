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
#ocvecs=( "OC_RP_2G1 OC_EC_2P1G1" )
#ocvecs=( "OC_RP_2G1 OC_RP_2G1" )

# test repetitions
REP=3

# ------------------

cd $HOME/daos-tests/google/daos
test_name=patternA
dummy_daos="false"
posix_cont="false"
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

    out=$(create_pool_cont $posix_cont $dummy_daos $servers fdb_hammer)
    code=$?
    [ $code -ne 0 ] && echo "create_pool_cont failed" && echo "${out}" && return
    pool=$(echo "$out" | grep "POOL: " | awk '{print $2}')
    cont_id=$(echo "$out" | grep "CONT: " | awk '{print $2}')
    echo "Pool is: $pool"
    echo "Cont is: $cont_id"

    out=$(./fdb_hammer/submitter.sh $c test_fdb_hammer -PRV tcp \
        --osize ${osize} \
        --ock ${ocvec[0]} --oca ${ocvec[1]} --daos \
        $n $WR 0 -P $pool -C $cont_id \
	--nsteps 100 --nparams 10)
#        --nmembers= --ndatabases= --nlevels=
    echo "$out"
    jid=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    while squeue | grep -q -e "^ *$jid .* ${USER::8} " ; do sleep 5 && echo "Sleeping..."; done

    out=$(./fdb_hammer/submitter.sh $c test_fdb_hammer -PRV tcp \
        --osize ${osize} \
        --ock ${ocvec[0]} --oca ${ocvec[1]} --daos \
        $n 0 $WR -P $pool -C $cont_id \
	--nsteps 100 --nparams 10)
#        --nmembers= --ndatabases= --nlevels=
    echo "$out"
    jid=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    while squeue | grep -q -e "^ *$jid .* ${USER::8} " ; do sleep 5 && echo "Sleeping..."; done

    out=$(destroy_pool_cont $dummy_daos $servers fdb_hammer)
    code=$?
    [ $code -ne 0 ] && echo "destroy_pool_cont failed for N=$n" && return
done
done
done
res_dir=runs/${servers}/fdb_hammer/${tname}/${ocname}/${osize}
mkdir -p $res_dir
mv runs/fdb_hammer_* ${res_dir}/
done
done
