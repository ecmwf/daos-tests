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
test_name=patternA
servers="octa_server"
osizes=("1MiB")
posix_backend="true"
posix_cont="false"
#dummy_daos="false"
ocvecs=( "OC_SX OC_S1" )
#C=(1 2 4 6)
C=(16)
REP=3
WR=10000
sleep=0
source pool_helpers.sh
backend_arg="--daos"
#dummy_daos_arg=
tname=${test_name}
#[[ "$dummy_daos" == "true" ]] && tname=${tname}_dummy && dummy_daos_arg="--dummy"
[[ "$posix_backend" == "true" ]] && tname=${tname}_posix && backend_arg="--posix"
for osize in "${osizes[@]}" ; do
for ocvec in "${ocvecs[@]}" ; do
ocname=$(echo ${ocvec} | tr ' ' '_')
ocvec=($(echo "$ocvec"))
for c in "${C[@]}" ; do
[ $c -eq 1 ] && N=(1 4 8 12 16 32 48)
#[ $c -eq 1 ] && N=(32 48)
#[ $c -eq 2 ] && N=(1 4 8 12 16 32 48)
[ $c -eq 2 ] && N=(8 16 32 48)
#[ $c -eq 2 ] && N=(48)
[ $c -eq 4 ] && N=(1 4 8 12 16 32 48)
#[ $c -eq 4 ] && N=(8 16 32 48)
[ $c -eq 6 ] && N=(1 4 8 12 16 32 48)
#[ $c -eq 8 ] && N=(1 8 16 32 48 64)
[ $c -eq 8 ] && N=(8 16 32 48)
[ $c -eq 10 ] && N=(16 32 48 64)
#[ $c -eq 12 ] && N=(16 32 48 64)
[ $c -eq 12 ] && N=(1 4 8 12)
#[ $c -eq 12 ] && N=(32 48)
#[ $c -eq 14 ] && N=(16 32 48 64)
[ $c -eq 14 ] && N=(1 4 8 12)
[ $c -eq 16 ] && N=(1 4 8 12)
#[ $c -eq 16 ] && N=(16 32 48)
[ $c -eq 18 ] && N=(16 32 48 64)
#[ $c -eq 20 ] && N=(16 32 48 64)
[ $c -eq 20 ] && N=(1 4 8 12)
[ $c -eq 24 ] && N=(1 8 16 32 48 64)
for n in "${N[@]}" ; do
for r in `seq 1 $REP` ; do
    #echo "### Pattern A, ${ocvec[@]}, ${osize}, C=$c, N=$n, rep=$r ###"
    echo "### Pattern A, ${osize}, C=$c, N=$n, rep=$r ###"

    #out=$(create_pool_cont $posix_cont $dummy_daos $servers)
    out=$(create_pool_cont $posix_cont $posix_backend $servers fdb_hammer)
    code=$?
    [ $code -ne 0 ] && echo "create_pool_cont failed" && return
    pool_id=$(echo "$out" | grep "POOL: " | awk '{print $2}')
    #cont=testcont
    echo "Pool is: $pool_id"
    #echo "Cont is: $cont"
    fdbroot=test_fdb_hammer_tmp
    echo "FDB Root is: $fdbroot"

    out=$(./fdb_hammer/submitter.sh $c test_fdb_hammer -PRV tcp \
        --osize ${osize} \
        --ock ${ocvec[0]} --oca ${ocvec[1]} ${backend_arg} \
        $n $WR 0 -R $fdbroot -P $pool_id \
        --nsteps 100 --nparams 10 \
        $dummy_daos_arg)
#        $n $WR 0 -P $pool_id -C $cont \
#        --nmembers= --ndatabases= --nlevels=
    echo "$out"
    jid=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    while squeue | grep -q -e "^ *$jid .* $USER " ; do sleep 5 && echo "Sleeping..."; done

    out=$(./fdb_hammer/submitter.sh $c test_fdb_hammer -PRV tcp \
        --osize ${osize} \
        --ock ${ocvec[0]} --oca ${ocvec[1]} ${backend_arg} \
        $n 0 $WR -R $fdbroot -P $pool_id \
        --nsteps 100 --nparams 10 \
        $dummy_daos_arg)
#        $n 0 $WR -P $pool_id -C $cont \
#        --nmembers= --ndatabases= --nlevels=
    echo "$out"
    jid=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    while squeue | grep -q -e "^ *$jid .* $USER " ; do sleep 5 && echo "Sleeping..."; done

    out=$(./fdb_hammer/submitter.sh $c test_fdb_hammer -PRV tcp \
        --osize ${osize} \
        --ock ${ocvec[0]} --oca ${ocvec[1]} ${backend_arg} \
        $n 0 $WR -R $fdbroot -P $pool_id \
        --nsteps 10 --nparams 10 -L \
        $dummy_daos_arg)
#        --nmembers= --ndatabases= --nlevels=
    echo "$out"
    jid=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    while squeue | grep -q -e "^ *$jid .* $USER " ; do sleep 5 && echo "Sleeping..."; done

    #out=$(destroy_pool_cont $dummy_daos)
    out=$(destroy_pool_cont $posix_backend fdb_hammer)
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
