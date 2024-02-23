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

cd $HOME/daos-tests/ngio
test_name=patternC
servers="ten_server"
osizes=("1MiB")
posix_cont="false"
dummy_daos="false"
ocvecs=( "OC_SX OC_S1" )
#C=(1 2 4 6)
C=(20)
REP=3
WR=2000
sleep=0
source pool_helpers.sh
dummy_daos_arg=
tname=${test_name}
[[ "$dummy_daos" == "true" ]] && tname=${tname}_dummy && dummy_daos_arg="--dummy"
for osize in "${osizes[@]}" ; do
for ocvec in "${ocvecs[@]}" ; do
ocname=$(echo ${ocvec} | tr ' ' '_')
ocvec=($(echo "$ocvec"))
res_dir=runs/${servers}/fdb_hammer/${tname}/${ocname}/${osize}
for c in "${C[@]}" ; do
if [ "$c" -ge 2 ] ; then
c2=$(( c / 2 ))
[ $c -eq 1 ] && N=(1 8 16 32 48 64)
#[ $c -eq 2 ] && N=(1 8 16 32 48 64)
[ $c -eq 2 ] && N=(16 32 48)
#[ $c -eq 4 ] && N=(1 8 16 32 48 64)
[ $c -eq 4 ] && N=(16 32 48)
[ $c -eq 6 ] && N=(1 8 16 32 48 64)
#[ $c -eq 8 ] && N=(1 8 16 32 48 64)
[ $c -eq 8 ] && N=(16 32 48)
[ $c -eq 10 ] && N=(16 32 48 64)
[ $c -eq 12 ] && N=(16 32 48 64)
#[ $c -eq 14 ] && N=(16 32 48 64)
[ $c -eq 14 ] && N=(16 32)
#[ $c -eq 16 ] && N=(1 8 16 32 48 64)
[ $c -eq 16 ] && N=(16 32)
[ $c -eq 18 ] && N=(16 32 48 64)
#[ $c -eq 20 ] && N=(16 32 48 64)
[ $c -eq 20 ] && N=(16 32)
#[ $c -eq 20 ] && N=(32)
[ $c -eq 24 ] && N=(1 8 16 32 48 64)
#1 3 4 6 9 12 18 24 36 48)
for n in "${N[@]}" ; do
for r in `seq 1 $REP` ; do
    echo "### Pattern C, ${ocvec[@]}, ${osize}, C=$c, N=$n, rep=$r ###"

    out=$(create_pool_cont $posix_cont $dummy_daos $servers fdb_hammer)
    code=$?
    [ $code -ne 0 ] && echo "create_pool_cont failed" && return
    pool_id=$(echo "$out" | grep "POOL: " | awk '{print $2}')
    cont=testcont
    echo "Pool is: $pool_id"
    echo "Cont is: $cont"

    out=$(./fdb_hammer/submitter.sh $c2 test_fdb_hammer -PRV tcp \
            --osize ${osize} \
            --ock ${ocvec[0]} --oca ${ocvec[1]} --daos \
            $n $WR 0 -P $pool_id -C $cont \
            --nsteps 10 --nparams 10 \
            $dummy_daos_arg)
#            --nmembers= --ndatabases= --nlevels=
    echo "$out"
    jid=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    while squeue | grep -q -e "^ *$jid .* $USER " ; do sleep 5 && echo "Sleeping..."; done

    mkdir -p ${res_dir}/setup
    mv runs/fdb_hammer_${c2}_test_fdb_hammer_-PRV_tcp_*_${n}_${WR}_0_-P_${pool_id}_-C_${cont}_* ${res_dir}/setup/

    out=$(./fdb_hammer/submitter.sh $c2 test_fdb_hammer -PRV tcp \
            --osize ${osize} \
            --ock ${ocvec[0]} --oca ${ocvec[1]} --daos \
            $n $WR 0 -P $pool_id -C $cont \
            --nsteps 10 --nparams 10 \
            $dummy_daos_arg)
#            --nmembers= --ndatabases= --nlevels=
    echo "$out"
    jid1=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    out=$(./fdb_hammer/submitter.sh $c2 test_fdb_hammer -PRV tcp \
            --osize ${osize} \
            --ock ${ocvec[0]} --oca ${ocvec[1]} --daos \
            $n 0 $WR -P $pool_id -C $cont \
            --nsteps 10 --nparams 10 \
            $dummy_daos_arg)
    echo "$out"
    jid2=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    while squeue | grep -q -e "^ *${jid1} .* $USER " -e "^ *${jid2} .* $USER " ; do
        sleep 5 && echo "Sleeping..."
    done

    out=$(destroy_pool_cont $dummy_daos fdb_hammer)
    code=$?
    [ $code -ne 0 ] && echo "destroy_pool_cont failed for N=$n" && return
done
done
fi
done
mkdir -p $res_dir
mv runs/fdb_hammer_* ${res_dir}/
done
done
