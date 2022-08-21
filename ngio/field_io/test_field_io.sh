#!/usr/bin/env bash

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

start=`date +%s`

test_src_dir=$HOME/daos-tests
dmg_config=$HOME/daos-tests/ngio/config/daos_control.yaml
sudo_client=false 
pool_scm=5G
pool_nvme=26G

U=0
S=0
L=0
H=0
I=0
num_nodes=0
n_to_write=0
n_to_read=0
osize=1MiB
pool_id=
cont_id=
all_to_files=0
pool_created=0

POSITIONAL=()
while [[ $# -gt 0 ]] ; do
key="$1"
case $key in
    -h|--help)
    echo -e "\
Usage:\n\n\
test_field_io.sh N W R [options]\n\n\
N: number of parallel clients to spawn\n\n\
W: number of times a client will sequentially run daos_field_write\n\n\
R: number of times a client will sequentially run daos_field_read\n\n\
Available options:\n\n\
--osize <n>MiB\n\nspecify an object size to be used for the DAOS arrays. The input \
data file of 1MiB will be read n times to create the data buffer to be written to a \
new DAOS array.\n\n\
-U|--unique\n\nset this flag to have all writers/readers write/read fields \
into/from separate unique index entries instead of into/from a same index entry. The data \
written/read is the same even if requesting unique index entries.\n\n\
-S|--sleep <s>\n\ns is the number of seconds to sleep between sequential Ws and Rs.\n\
0 by default\n\n\
-L|--span-length <l>\n\nl is the length in seconds of the time span over which to \
spawn the N clients.\nl must be > 0.\nl should be << N.\n0 by default (burst mode)\n\n\
-H|--hold\n\nset this flag to have each client sleep for L - x seconds \
right after having established a connection with the DAOS pool. \
x is the amount of time each particular client c (from 1 to N) has waited \
before being spawned:\n\
   x = (c - 1) % N\n\n\
--num-nodes <n>\n\nn is the number of client nodse simultaneously running this script \
(used to generate uuids if --unique is set).\n0 by default\n\n\
-I|--node-id <i>\n\ni is an id used to represent the client node this script is \
running on (used to generate uuids if --unique is set).\n0 by default\n\n\
-P|--pool <uuid>\n\nUUID of a DAOS pool to use. If not porivded, one will be created and \
destroyed.\n\n\
-C|--container <uuid>\n\nUUID of a container to use. If not provided, one will be created \
and destroyed.\n\n\
--n-to-write <nw>\n\nin cases where --unique is specified, each writer client will attempt \
writing fields into W different index entries. --n-to-write can be specified to have each \
writer (re-)write up to nw different index entries in a round-robin mode.\n\n\
--n-to-read <nr>\n\nin cases where --unique is specified, each reader client will attempt \
reading fields from R different index entries. --n-to-read can be specified to have each \
reader (re-)read up to nr different index entries in a round-robin mode.\n\n\
-A|--all-to-files\n\nset this flag for all reads to store read data in a separate file ending \
with _<read_id>_<node_id>, with 4 digits each tag. This will trigger individual read result \
comparison check\n\n\
-h|--help\n\nshow this menu\
"
    exit 0
    ;;
    --osize)
    osize="$2"
    shift
    shift
    ;;
    -U|--unique)
    U=1
    shift
    ;;
    -S|--sleep)
    S="$2"
    shift
    shift
    ;;
    -L|--span-length)
    L="$2"
    shift
    shift
    ;;
    -H|--hold)
    H=1
    shift
    ;;
    --num-nodes)
    num_nodes="$2"
    shift
    shift
    ;;
    -I|--node-id)
    I="$2"
    shift
    shift
    ;;
    --n-to-write)
    n_to_write="$2"
    shift
    shift
    ;;
    --n-to-read)
    n_to_read="$2"
    shift
    shift
    ;;
    -A|--all-to-files)
    all_to_files=1
    shift
    ;;
    -P|--pool)
    pool_id="$2"
    shift
    shift
    ;;
    -C|--container)
    cont_id="$2"
    shift
    shift
    ;;
    *)
    POSITIONAL+=( "$1" )
    shift
    ;;
esac
done
set -- "${POSITIONAL[@]}"

if [ ${#POSITIONAL[@]} -ne 3 ] ; then
    echo "Exactly 3 positional arguments were expected. Check test_field_io.sh --help."
    exit 1
fi

N=$1
W=$2
R=$3

[ $n_to_write -eq 0 ] && n_to_write=$W
if [ $n_to_read -eq 0 ] ; then
	if [ $n_to_write -gt 0 ] ; then
		n_to_read=$n_to_write
	else
		n_to_read=$R
	fi
fi

if [ $W -eq 0 ] && [ $R -gt 0 ] && [ $n_to_read -lt 1 ] ; then
	echo "R > 0 but no fields available apparently. Write fields and signal with --n-to-read."
	exit 1
fi

echo "$osize" | grep -q -E '^[0-9]{1,}MiB$' || (echo "Osize unreadable: $osize." && exit 1)

s=
[[ "$sudo_client" == "true" ]] && s="sudo -E"

[ ! -d $test_src_dir ] && echo "daos-tests directory not found." && exit 1

function pin {
	local x=$1
	local ch=$2
	local co=$3
	local ht=$4
	x=$(( x - 1 ))
	local a=$(( x % ch ))
	local tot=$(( ch * co ))
	local of=0
	if [ "$ht" -eq 1 ] ; then
		tot=$(( tot * 2 ))
		[ "$(( x % tot ))" -ge "$(( ch * co ))" ] && of=$(( ch * co ))
	fi
	local i=$(( ( (x % tot) - a) % (ch * co) / ch ))
	local y=$(( of + a * co + i ))
	echo "$y"
}

tmp_dir=$(mktemp -d -t test_field_io_XXX)
cd $tmp_dir

# Create a DAOS pool and container

if [ -z "$pool_id" ] ; then
	group=$($s id -g -n)
	user=$($s id -u -n)
	out=$($s dmg pool create -s $pool_scm -n $pool_nvme -g $group -u $user -i -o $dmg_config test)
	pool_created=1
	out2=$(echo "$out" | grep "UUID")
        export pool_id="${out2##*UUID                 : }"
	echo "Pool create succeeded"
else
	echo "Skipping pool create"
fi

if [ -z "$cont_id" ] ; then
	out=$($s daos container create test)
	export cont_id="${out##*container }"
	echo "Cont create succeeded"
else
	echo "Skipping container create"
fi

cd $tmp_dir
cp $test_src_dir/src/field_io/share/daos_field_io/testdata .
cmp_n=$(stat -c%s testdata)

# Run the clients

# real MARS/FDB syntax uses '/' in step and grid, instead of '-' used here. This is
# because if using the filesystem-backed dummy DAOS, where objects are mapped
# to files, slashes are not supported in object (file) names.
index_key='{"class":"od","date":"20200306"}'
store_key='{"stream":"oper","levtype":"sfc","param":"10u","step":"0-12","time":"00","type":"fc","expver":"0001","grid":"0.5-0.5"}'

n_chips=$(cat /proc/cpuinfo | grep "physical id" | sort -u | wc -l)
n_cores=$(cat /proc/cpuinfo | grep "core id" | sort -u | wc -l)
ht=0
n_procs=$(cat /proc/cpuinfo | grep "processor" | sort -u | wc -l)
[ "$n_procs" -gt "$(( n_cores * n_chips ))" ] && ht=1

function client {
	local client_start=`date +%s`

	local i=$1

	local failed=0
	local which_failed=
	local sep=
	local out=

	local lag=
	local hold=0

	local prof=
	local prof_sep=

	local log=
	local log_sep=

	[ $L -ne 0 ] && lag=$(($i % $L)) && hold=$(($L - $lag)) && sleep $lag
	[ $H -eq 0 ] && hold=0

	local pin_proc=$(pin $((i + 1)) $n_chips $n_cores $ht)

	local client_index_key="$index_key"
    # The index_key modification in the following line ensures low 
    # contention in forecast index, as each client process uses a unique
    # most-significant part for the field identifier.
    # If willing to run the field I/O benchmarks with high contention, the 
    # following line has to be commented out.
	client_index_key=$(echo "$index_key" | sed -e "s/\"}/,\"index\":\"$I,$i\"}/")

	if [ $W -gt 0 ] ; then
		w_bin=$(which daos_field_write)
		out=$($s taskset -c $pin_proc $w_bin $pool_id $cont_id \
			"${client_index_key}" "${store_key}" \
			testdata ${osize%*MiB} $W $U $n_to_write $hold $S $I $i 2>&1)
		[ $? != 0 ] && failed=1 && which_failed="${which_failed}${sep}write" \
			&& sep="; " && log="${log}"${log_sep}"log: $out" && log_sep="\n"
		prof="${prof}"${prof_sep}$(echo "$out" | grep -e "Profiling" -e "Processor" -e "Timestamp") && prof_sep="\n"
		hold=0
	fi

    # The following index_key modification is used to force each client node to read data 
    # written by another node, to avoid hitting local caches, if any, with data written
    # previously by the node running this script.
    # If willing to read same data as written and possibly hit local cache, the first line
    # has to be replaced by I2=$I.
    #I2=$I
    [ $num_nodes -ne 0 ] && I2=$(( (I + 1) % $num_nodes )) || I2=$I
	client_index_key=$(echo "$index_key" | sed -e "s/\"}/,\"index\":\"${I2},$i\"}/")
	if [ $R -gt 0 ] ; then
		r_bin=$(which daos_field_read)
		out=$($s taskset -c $pin_proc $r_bin $pool_id $cont_id \
			"${client_index_key}" "${store_key}" \
			testdata_$i $R $U $n_to_read $hold $S ${I2} $i $all_to_files 2>&1)
		[ $? != 0 ] && failed=1 && which_failed="${which_failed}${sep}read" \
			&& sep="; " && log="${log}"${log_sep}"log: $out" && log_sep="\n"
		prof="${prof}"${prof_sep}$(echo "$out" | grep -e "Profiling" -e "Processor" -e "Timestamp") && prof_sep="\n"

		if [ $failed -eq 0 ] && [[ "${osize}" == "1MiB" ]] ; then

			if [ $all_to_files -eq 1 ] ; then
				outs=($(ls testdata_$i_*))
				for of in "${outs[@]}" ; do
					$s cmp testdata $of -n $cmp_n
					[ $? != 0 ] && failed=1 \
					&& which_failed="${which_failed}${sep}read iter cmp" \
					&& sep="; " \
					&& log="${log}"${log_sep}"Client iteration cmp failed: $of" \
					&& log_sep="\n"
				done
			else
				$s cmp testdata testdata_$i -n $cmp_n
				[ $? != 0 ] && failed=1 \
				&& which_failed="${which_failed}${sep}read final cmp" \
				&& sep="; " \
				&& log="${log}"${log_sep}"Client final cmp failed" \
				&& log_sep="\n"
			fi
		fi
	fi

	[ $failed -ne 0 ] && echo "Node $I client $i failed at: $which_failed" \
		&& echo -e "${log}" && echo -e "${prof}" && return

	local client_end=`date +%s`
	local client_wc_time=$((client_end-client_start))

	echo -e "Node $I client $i succeeded\n${prof}"
	echo "Profiling node $I client $i - total wc time: $client_wc_time"
}

module load cmake

end=`date +%s`

setup_time=$((end-start))

start=`date +%s`

for i in $(seq 0 $((N - 1))) ; do
	client $i &
done

wait

if [ $U -eq 0 ] ; then
	failed=0

	r_bin=$(which daos_field_read)
	out=$($s $r_bin $pool_id $cont_id "${index_key}" "${store_key}" testdata_final 1 0 1 0 0 0 $N 0 2>&1)
	[ $? != 0 ] && failed=1 && echo "Final read failed"

	if [ $failed -eq 0 ] && [[ "${osize}" == "1MiB" ]] ; then
		$s cmp testdata testdata_final -n $cmp_n
		[ $? != 0 ] && failed=1 && echo "Final cmp failed"
	fi

	[ $failed -eq 0 ] && echo "Final read and cmp succeeded"
fi

end=`date +%s`

wc_time=$((end-start))

start=`date +%s`

if [ $pool_created -eq 1 ] ; then
	echo "Starting destroy"
	$s dmg pool destroy --force -i -o $dmg_config test
else
	echo "Skipping destroy"
fi

cd
rm -rf $tmp_dir

end=`date +%s`

teardown_time=$((end-start))

echo "Profiling node $I - test_field_io setup wc time: $setup_time"
echo "Profiling node $I - test_field_io all clients wc time: $wc_time"
echo "Profiling node $I - test_field_io teardown wc time: $teardown_time"
