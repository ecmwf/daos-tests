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
servers="dual_server"
rep_modes=( "segment" )
osizes=("1MiB" "5MiB" "10MiB" "20MiB")
ocs=("S1" "S2" "SX")
C=(1 2 4 8)
REP=10
WR=100
apis=(DAOS)
sleep=0
source pool_helpers.sh
for rep_mode in "${rep_modes[@]}" ; do
tname=${test_name}
[[ "$rep_mode" == "segment" ]] && tname=${test_name}_segment
[ $sleep -gt 0 ] && tname=${tname}_sleep
[ $sleep -gt 1 ] && tname=${tname}${sleep}
for api in "${apis[@]}" ; do
posix_cont=false
[[ "$api" == "DFS" ]] && posix_cont=true
[[ "$api" == "MPIIO" ]] && posix_cont=true
create_directory=false
[[ "$api" == "POSIX" ]] && create_directory=true
for osize in "${osizes[@]}" ; do
for oc in "${ocs[@]}" ; do
ocname=$oc
for c in "${C[@]}" ; do
[ $c -eq 1 ] && N=(1 4 12 24 36 48 72 96 144 192)
[ $c -eq 2 ] && N=(1 4 12 18 24 36 48 72 96 144)
[ $c -eq 4 ] && N=(1 4 6 9 12 18 24 36 48 72)
[ $c -eq 8 ] && N=(1 3 4 6 9 12 18 24 36 48)
[ $c -eq 10 ] && N=(1 3 4 6 9 12 18 24 36 48)
[ $c -eq 12 ] && N=(1 3 4 6 9 12 18 24 36 48)
[ $c -eq 14 ] && N=(1 3 4 6 9 12 18 24 36 48)
[ $c -eq 16 ] && N=(1 3 4 6 9 12 18 24 36 48)
[ $c -eq 18 ] && N=(1 3 4 6 9 12 18 24 36 48)
[ $c -eq 20 ] && N=(1 3 4 6 9 12 18 24 36 48)
for n in "${N[@]}" ; do
for r in `seq 1 $REP` ; do

    echo "### IOR Pattern A ${rep_mode}, ${oc}, ${osize}, API=$api, C=$c, N=$n, rep=$r ###"

    out=$(create_pool_cont $posix_cont $create_directory $servers)
    code=$?
    [ $code -ne 0 ] && echo "create_pool_cont failed" && return
    pool_id=$(echo "$out" | grep "POOL: " | awk '{print $2}')
    cont_id=$(echo "$out" | grep "CONT: " | awk '{print $2}')
    echo "Pool is: $pool_id"
    echo "Cont is: $cont_id"

    out=$(./ior/submitter.sh $c ior $api tcp $n $WR write $rep_mode \
        true true true $sleep $oc $osize $pool_id $cont_id)
    echo "$out"
        jid=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    while squeue | grep -q -e "^ *$jid .* $USER " ; do sleep 5 && echo "Sleeping..."; done
    out=$(./ior/submitter.sh $c ior $api tcp $n $WR read $rep_mode \
        true true false $sleep $oc $osize $pool_id $cont_id)
    echo "$out"
        jid=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    while squeue | grep -q -e "^ *$jid .* $USER " ; do sleep 5 && echo "Sleeping..."; done

    out=$(destroy_pool_cont $create_directory)
    code=$?
    [ $code -ne 0 ] && echo "destroy_pool_cont failed for N=$n" && return

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
