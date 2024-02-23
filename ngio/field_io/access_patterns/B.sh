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
test_name=patternB
servers="dual_server"
simplified=( "" "--simple" "--simple-kvs" )
osizes=("1MiB" "5MiB" "10MiB" "20MiB")
posix_cont="false"
dummy_daos="false"
ocvecs=( "OC_S1 OC_S1 OC_S1" "OC_S2 OC_S2 OC_S2" "OC_SX OC_SX OC_SX" "OC_SX OC_S2 OC_S1" "OC_SX OC_SX OC_S1" )
C=(1 2 4 8)
REP=10
WR=2000
sleep=0
source pool_helpers.sh
for s in "${simplified[@]}" ; do
dummy_daos_arg=
tname=${test_name}
[[ "$dummy_daos" == "true" ]] && tname=${tname}_dummy && dummy_daos_arg="--dummy"
[[ "$s" == "--simple" ]] && tname=${tname}_simple
[[ "$s" == "--simple-kvs" ]] && tname=${tname}_simple_kvs
[ $sleep -gt 0 ] && tname=${tname}_sleep
[ $sleep -gt 1 ] && tname=${tname}${sleep}
for osize in "${osizes[@]}" ; do
for ocvec in "${ocvecs[@]}" ; do
ocname=$(echo ${ocvec} | tr ' ' '_')
ocvec=($(echo "$ocvec"))
res_dir=runs/${servers}/field_io/${tname}/${ocname}/${osize}
for c in "${C[@]}" ; do
if [ "$c" -ge 2 ] ; then
c2=$(( c / 2 ))
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
    echo "### Pattern B $s, ${ocvec[@]}, ${osize}, C=$c, N=$n, rep=$r ###"

    out=$(create_pool_cont $posix_cont $dummy_daos $servers)
    code=$?
    [ $code -ne 0 ] && echo "create_pool_cont failed" && return
    pool_id=$(echo "$out" | grep "POOL: " | awk '{print $2}')
    cont_id=$(echo "$out" | grep "CONT: " | awk '{print $2}')
    echo "Pool is: $pool_id"
    echo "Cont is: $cont_id"

    out=$(./field_io/submitter.sh $c2 test_field_io -PRV tcp $s --osize ${osize} \
            --ocm ${ocvec[0]} --oci ${ocvec[1]} --ocs ${ocvec[2]} \
            $n 1 0 -P $pool_id -C $cont_id --unique --n-to-write 1 \
            -L 1 $dummy_daos_arg)
    echo "$out"
    jid=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    while squeue | grep -q -e "^ *$jid .* $USER " ; do sleep 5 && echo "Sleeping..."; done

    mkdir -p ${res_dir}/setup
    mv runs/daos_${c2}_test_field_io_-PRV_tcp_*_${n}_1_0_-P_${pool_id}_-C_${cont_id}_* ${res_dir}/setup/

    span_length=5
    io_start_barrier=$(( $(date +%s) + ${span_length} + 15 ))
    out=$(./field_io/submitter.sh $c2 test_field_io -PRV tcp $s --osize ${osize} \
            --ocm ${ocvec[0]} --oci ${ocvec[1]} --ocs ${ocvec[2]} \
            $n $WR 0 -P $pool_id -C $cont_id --unique --n-to-write 1 \
            --sleep $sleep -L ${span_length} -B $io_start_barrier $dummy_daos_arg)
    echo "$out"
    jid1=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    out=$(./field_io/submitter.sh $c2 test_field_io -PRV tcp $s --osize ${osize} \
            --ocm ${ocvec[0]} --oci ${ocvec[1]} --ocs ${ocvec[2]} \
            $n 0 $WR -P $pool_id -C $cont_id --unique --n-to-read 1 \
            --sleep $sleep -L ${span_length} -B $io_start_barrier $dummy_daos_arg)
    echo "$out"
    jid2=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    while squeue | grep -q -e "^ *${jid1} .* $USER " -e "^ *${jid2} .* $USER " ; do
        sleep 5 && echo "Sleeping..."
    done

    out=$(destroy_pool_cont $dummy_daos)
    code=$?
    [ $code -ne 0 ] && echo "destroy_pool_cont failed for N=$n" && return
done
done
fi
done
mkdir -p $res_dir
mv runs/daos_* ${res_dir}/
done
done
done
