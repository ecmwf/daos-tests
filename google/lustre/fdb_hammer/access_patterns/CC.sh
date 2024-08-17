#ready=0
#while [ $ready -eq 0 ] ; do
#  echo "Waiting for Lustre to be ready..."
#  res=$(getent ahostsv4 mystore-manager | grep RAW | awk '{print $1}' | wc -l)
#  [ $res -ne 0 ] && ready=1 && continue
#  sleep 30
#done

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

cd $HOME/daos-tests/google/lustre
test_name=patternC
servers="sixteen_server"
osizes=("1MiB")
posix_backend="true"
ocvecs=( "OC_SX OC_S1" )
#C=(2 4 8)
#C=(48 32 16)
C=(48)
REP=3
WR=10000
sleep=0
source pool_helpers.sh
backend_arg="--posix"
tname=${test_name}
[[ "$posix_backend" == "true" ]] && tname=${tname}_posix
for osize in "${osizes[@]}" ; do
for ocvec in "${ocvecs[@]}" ; do
ocname=$(echo ${ocvec} | tr ' ' '_')
ocvec=($(echo "$ocvec"))
res_dir=runs/${servers}/fdb_hammer/${tname}/${ocname}/${osize}
for c in "${C[@]}" ; do
if [ "$c" -ge 2 ] ; then
c2=$(( c / 2 ))
#[ $c -eq 1 ] && N=(16 32 48 64)
#[ $c -eq 1 ] && N=(32 48)
[ $c -eq 1 ] && N=(32 24 16 12 8 4 1)
#[ $c -eq 2 ] && N=(1 8 16 32 48 64)
[ $c -eq 2 ] && N=(32 48)
#[ $c -eq 2 ] && N=(48)
#[ $c -eq 4 ] && N=(1 8 16 32 48 64)
[ $c -eq 4 ] && N=(8)
#[ $c -eq 8 ] && N=(1 8 16 32 48 64)
#[ $c -eq 8 ] && N=(32 48)
[ $c -eq 8 ] && N=(32 24 16 12 8 4 1)
[ $c -eq 10 ] && N=(16 32 48 64)
#[ $c -eq 12 ] && N=(16 32 48 64)
[ $c -eq 12 ] && N=(32 48)
#[ $c -eq 14 ] && N=(16 32 48 64)
[ $c -eq 14 ] && N=(16 32 48)
#[ $c -eq 16 ] && N=(1 8 48 64)
[ $c -eq 16 ] && N=(32 24 16 12 8 4 1)
[ $c -eq 18 ] && N=(16 32 48 64)
#[ $c -eq 20 ] && N=(16 32 48 64)
#[ $c -eq 20 ] && N=(16 32 48)
[ $c -eq 20 ] && N=(4)
[ $c -eq 24 ] && N=(1 8 16 32 48 64)
[ $c -eq 32 ] && N=(32 24 16 12 8 4 1)
#[ $c -eq 48 ] && N=(32 24 16 12 8 4 1)
#[ $c -eq 48 ] && N=(24 16 12 8 4 1)
[ $c -eq 48 ] && N=(16)
[ $c -eq 80 ] && N=(4)
[ $c -eq 160 ] && N=(4)
for n in "${N[@]}" ; do
for r in `seq 1 $REP` ; do
    echo "### Pattern C, ${osize}, C=$c, N=$n, rep=$r ###"

    nnodes=$c
    nodes_ready=0
    retried=0
    while [ $nodes_ready -eq 0 ] ; do
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
              sinfo -N | tail -n+2 | awk '{print $1}' | xargs -I{} sudo su - slurm -c 'scontrol update nodename={} state=POWER_DOWN'
              echo "Waiting for all nodes to be idle~..." && sleep 90
	      out=$(sinfo -N | tail -n+2 | grep -v -e 'idle~' | wc -l)
	    done
        fi
    done
    echo "Client nodes provisioned"

    sleep 5

    out=$(create_pool_cont $posix_cont $posix_backend $servers fdb_hammer)
    code=$?
    [ $code -ne 0 ] && echo "create_pool_cont failed" && return
    pool_id=$(echo "$out" | grep "POOL: " | awk '{print $2}')
    #cont=testcont
    echo "Pool is: $pool_id"
    #echo "Cont is: $cont"
    fdbroot=test_fdb_hammer_tmp
    echo "FDB Root is: $fdbroot"

    out=$(./fdb_hammer/submitter.sh $c2 test_fdb_hammer -PRV tcp \
        --osize ${osize} \
        --ock ${ocvec[0]} --oca ${ocvec[1]} ${backend_arg} \
        $n $WR 0 -R $fdbroot -P $pool_id \
	--nsteps 100 --nparams 10)
#        $n $WR 0 -P $pool_id -C $cont \
#        --nmembers= --ndatabases= --nlevels=
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

    mkdir -p ${res_dir}/setup
    mv runs/fdb_hammer_${c2}_test_fdb_hammer_-PRV_tcp_*_${n}_${WR}_0_-R_${fdbroot}_-P_${pool_id}_* ${res_dir}/setup/

    nnodes=$c
    nodes_ready=0
    retried=0
    while [ $nodes_ready -eq 0 ] ; do
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
              sinfo -N | tail -n+2 | awk '{print $1}' | xargs -I{} sudo su - slurm -c 'scontrol update nodename={} state=POWER_DOWN'
              echo "Waiting for all nodes to be idle~..." && sleep 90
	      out=$(sinfo -N | tail -n+2 | grep -v -e 'idle~' | wc -l)
	    done
        fi
    done
    echo "Client nodes provisioned"

    sleep 5


    out=$(./fdb_hammer/submitter.sh $c2 test_fdb_hammer -PRV tcp \
        --osize ${osize} \
        --ock ${ocvec[0]} --oca ${ocvec[1]} ${backend_arg} \
        $n $WR 0 -R $fdbroot -P $pool_id \
	--nsteps 100 --nparams 10)
#        $n 0 $WR -P $pool_id -C $cont \
#        --nmembers= --ndatabases= --nlevels=
    echo "$out"
    jid1=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    out=$(./fdb_hammer/submitter.sh $c2 test_fdb_hammer -PRV tcp \
        --osize ${osize} \
        --ock ${ocvec[0]} --oca ${ocvec[1]} ${backend_arg} \
        $n 0 $WR -R $fdbroot -P $pool_id \
	--nsteps 100 --nparams 10)
#        $n 0 $WR -P $pool_id -C $cont \
#        --nmembers= --ndatabases= --nlevels=
    echo "$out"
    jid2=$(echo "$out" | grep -e "Submitted batch job" | awk '{print $4}')
    while squeue | grep -q -e "^ *${jid1} .* ${USER::8} " -e "^ *${jid2} .* ${USER::8} " ; do
        sleep 5
        echo "Sleeping..."
        res=$(getent ahostsv4 mystore-manager | grep RAW | awk '{print $1}' | wc -l)
        [ $res -eq 0 ] && echo "Cancelling..." && scancel ${jid1} ${jid2} && sleep 30 && next=1
    done
    [ $next -eq 1 ] && continue

    out=$(destroy_pool_cont $posix_backend $servers fdb_hammer)
    code=$?
    [ $code -ne 0 ] && echo "destroy_pool_cont failed for N=$n" && return
done
done
fi
done
mkdir -p $res_dir
sleep 2
mv runs/fdb_hammer_* ${res_dir}/
done
done
