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

I=0
num_nodes=1
n_to_write=0
n_to_read=0
osize=1MiB
pool_id=
cont_id=
fdb_list=0
pool_created=0

nmembers=
ndatabases=1

nsteps=
nlevels=
nparams=

backend=
fdb_root=

POSITIONAL=()
while [[ $# -gt 0 ]] ; do
key="$1"
case $key in
    -h|--help)
    echo -e "\
Usage:\n\n\
test_fdb_hammer.sh N W R [options]\n\n\
N: number of parallel clients (IO server writer processes or PGEN reader processes) to \
spawn\n\n\
W: number of times a client will sequentially run daos_field_write\n\n\
R: number of times a client will sequentially run daos_field_read\n\n\
fdb-hammer must be in PATH.\n\n\
Available options:\n\n\
--osize <n>MiB\n\nspecify an object size to be used for the DAOS arrays. The input \
data file of 1MiB will be read n times to create the data buffer to be written to a \
new DAOS array.\n\n\
--num-nodes <n>\n\nn is the number of client nodse simultaneously running this script \
(used to generate uuids if --unique is set).\n0 by default\n\n\
-I|--node-id <i>\n\ni is an id used to represent the client node this script is \
running on (used to generate uuids if --unique is set).\n0 by default\n\n\
-P|--pool <uuid>\n\nUUID of a DAOS pool to use.\n\n\
-C|--container <uuid>\n\nUUID of a container to use.\n\n\
-L|--list\n\nTest fdb-list instead of fdb-read.\n\n\
-h|--help\n\nshow this menu\
"
#
#nmembers: number of ensemble members to generate and archive data for among all parallel runs (on different nodes) of this script. Each member will be run separately on an equal portion of the available client nodes. The number of levels to generate and archive data for will be split among all parallel processes run for a member (potentially on multiple nodes)(i.e. num_nodes / nmembers * N if nmembers < num_nodes, or N / nmembers if nmembers >= num_nodes). The fdb-hammer processes launched by this script run will be configured to generate and archive data for the corresponding member or members. num_nodes must be divisible by nmembers if nmembers < num_nodes, otherwise nmembers must be a multiple of num_nodes and num_nodes * N must be divisible by nmembers. Takes num_nodes by default (i.e. a member per client node).
#
#ndatabases: number of databases (or database keys) a member will generate and archive data for. The total amount of parallel processes (potentially on different nodes) devoted to a member will be split in ndatabases groups, and each group will generate a full member with a different expver (and therefore different dbKey). The larger ndatabases, the less processes will be devoted to a member and the more levels a process will generate and archive data for to fulfil W and/or R I/Os. num_nodes * N / nmembers must be divisible by ndatabases and ndatabases must be <= 10. Takes a value of 1 by default.
#
#nsteps: N must be divisible by nsteps, if specified. If unspecified, by default it will take a value equal to nlevels and/or nparams, if these are unspecified too, such that W and/or R I/Os are fulfiled.
#
#nlevels: nlevels per process! not per member. Levels per member = nlevels * nprocs per member
#
#nparams:
#
    exit 0
    ;;
    --osize)
    osize="$2"
    shift
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
    -L|--list)
    fdb_list=1
    shift
    ;;
    -R|--fdbroot)
    fdb_root="/newlust/$2"
    shift
    shift
    ;;
    --nmembers)
    nmembers="$2"
    shift
    shift
    ;;
    --ndatabases)
    ndatabases="$2"
    shift
    shift
    ;;
    --nsteps)
    nsteps="$2"
    shift
    shift
    ;;
    --nlevels)
    nlevels="$2"
    shift
    shift
    ;;
    --nparams)
    nparams="$2"
    shift
    shift
    ;;
    --daos)
    backend="daos"
    shift
    ;;
    --posix)
    backend="posix"
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
    echo "Exactly 3 positional arguments were expected. Check test_fdb_hammer.sh --help."
    exit 1
fi

N=$1
W=$2
R=$3

[ "$num_nodes" -eq 0 ] && echo "num_nodes must be > 0" && exit 1
[ "$N" -eq 0 ] && echo "N must be > 0" && exit 1

# check backend
if [ -z "$backend" ] ; then
	echo "Either --daos or --posix must be specified."
	exit 1
fi

if [[ "$backend" == "daos" ]] ; then

    # Check DAOS pool and container

    if [ -z "$pool_id" ] ; then
        echo "An existing pool ID must be provided."
        exit 1
    fi

    if [ -z "$cont_id" ] ; then
        echo "An existing container ID must be provided."
        exit 1
    fi

else

    if [ -z "$fdb_root" ] ; then
        echo "An existing FDB root directory must be provided."
        exit 1
    fi

fi

# check nmembers
if [ -z "$nmembers" ] ; then
	nmembers=$num_nodes
	[ "$num_nodes" -eq 0 ] && nmembers=1
fi
if [ "$nmembers" -lt "$num_nodes" ] ; then
	(( "$num_nodes" % "$nmembers" != 0 )) && \
		echo "num_nodes must be divisible by nmembers if nmembers < num_nodes" && \
		exit 1
else
	(( "$nmembers" % "$num_nodes" != 0 )) && \
		echo "nmembers must be a multiple of num_nodes if nmembers >= num_nodes" && \
		exit 1
	(( ( "$num_nodes" * "$N" ) % "$nmembers" != 0 )) && \
		echo "num_nodes * N must be divisible by nmembers if nmembers >= num_nodes" && \
		exit 1
fi

# check ndatabases
[ "$ndatabases" -gt 10 ] && echo "ndatabases must be > 0 and <= 10" && exit 1
(( ( ( "$num_nodes" * "$N" ) / "$nmembers" ) % "$ndatabases" != 0 )) && \
	echo "num_nodes * N / nmembers must be divisible by ndatabases" && \
	exit 1

# check osize
echo "$osize" | grep -q -E '^[0-9]{1,}MiB$' || (echo "Osize unreadable: $osize." && exit 1)

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

tmp_dir=$(mktemp -d -t test_fdb_hammer_XXX)
cd $tmp_dir

# Run the clients

n_chips=$(cat /proc/cpuinfo | grep "physical id" | sort -u | wc -l)
n_cores=$(cat /proc/cpuinfo | grep "cpu cores" | sort -u | awk '{print $4}')
ht=0
n_procs=$(cat /proc/cpuinfo | grep "processor" | sort -u | wc -l)
[ "$n_procs" -gt "$(( n_cores * n_chips ))" ] && ht=1

#example input:
#--num-nodes 4
#-I 0
#-N 48
#-W 5000
#--ndatabases=1
#--nmembers=4
#--nsteps=10
#[--nlevels=]
#--nparams=10

function client {
	local client_start=`date +%s`

	local i=$1

	local failed=0
	local which_failed=
	local sep=
	local out=

	local prof=
	local prof_sep=

	local log=
	local log_sep=

	# pinning to both sockets:
	local pin_proc=$(pin $((i + 1)) $n_chips $n_cores $ht)

	# pinning to first socket only:
	#local pin_proc=$(pin $(( ( i + 1 ) * 2 - 1 )) $n_chips $n_cores $ht)

	[ "$W" -gt 0 ] && [ "$R" -gt 0 ] && echo "Either W or R must be 0" && exit 1
	[ "$fdb_list" -eq 1 ] && [ "$R" -eq 0 ] && echo "R must be > 0 if --list is enabled" && exit 1

	# local page cache busting
	[ "$W" -eq 0 ] && I=$(( ( I + 1 )  % num_nodes ))

	local dim=$(( W + R ))
	
	local nundefined=0

	if [ -z "$nsteps" ] ; then
		nundefined=$(( nundefined + 1 ))
	else
		(( dim % nsteps != 0 )) && \
			echo "W or R must be divisible by nsteps" && \
			exit 1
		dim=$(( dim / nsteps ))
	fi

	if [ -z "$nlevels" ] ; then
		nundefined=$(( nundefined + 1 ))
	else
		(( dim % nlevels != 0 )) && \
			echo "W or R must be divisible by nlevels" && \
			exit 1
		dim=$(( dim / nlevels ))
	fi

	if [ -z "$nparams" ] ; then
		nundefined=$(( nundefined + 1 ))
	else
		[ "$nparams" -gt 200 ] && \
			echo "nparams must be lesser or equal to 200" && \
			exit 1
		(( dim % nparams != 0 )) && \
			echo "W or R must be divisible by nparams" && \
			exit 1
		dim=$(( dim / nparams ))
	fi

	if [ "$nundefined" -gt 0 ] ; then
		dim=$(python3 -c "x=pow(${dim}, (1/${nundefined})); print(int(x)) if ((x%1)==0) else print('failed')")
		[[ "$dim" == "failed" ]] && \
			echo "W or R must be divisible by n. of undefined dims (${nundefined})" && \
			exit 1

		[ -z "$nsteps" ] && nsteps=$dim
		[ -z "$nlevels" ] && nlevels=$dim
		[ -z "$nparams" ] && nparams=$dim

		[ "$nparams" -gt 200 ] && \
			echo "nparams inferred to be ${nparams} but it must be lesser or equal to 200" && \
			exit 1

	else
		# assert dim=1 i.e. W=nsteps*nlevels*nparams
		[ "$dim" -ne 1 ] && \
			echo "W or R must be equal to nsteps * nlevels * nparams" && \
			exit 1
	fi

	local number=
	local database=
	local level=
	local procs_per_db=

	if [ "$num_nodes" -gt "$nmembers" ] ; then
		nodes_per_member=$(( num_nodes / nmembers ))
		number=$(( I / nodes_per_member + 1 ))

		procs_per_member=$(( N * nodes_per_member ))
		procs_per_db=$(( procs_per_member / ndatabases ))
		member_proc_i=$( (N * (I % nodes_per_member) + i ))
		database=$(( member_proc_i / procs_per_db ))

		database_proc_i=$(( member_proc_i % procs_per_db ))
		level=$(( ( nlevels * database_proc_i ) + 1 ))
	else
		members_per_node=$(( nmembers / num_nodes ))
		procs_per_member=$(( N / members_per_node ))
		number=$(( ( I * members_per_node ) + ( i / procs_per_member ) + 1 ))

		procs_per_db=$(( procs_per_member / ndatabases ))
		member_proc_i=$(( i % procs_per_member ))
		database=$(( member_proc_i / procs_per_db ))

		database_proc_i=$(( member_proc_i % procs_per_db ))
		level=$(( ( nlevels * database_proc_i ) + 1 ))
	fi
 
	local expver="xxx${database}"

	local fdb_hammer=$(which fdb-hammer)

	if [ $W -gt 0 ] ; then
		#out=$($fdb_hammer \
		out=$(taskset -c $pin_proc $fdb_hammer \
			$tmp_dir/sample${osize} \
			--class=rd \
			--expver=$expver \
			--nsteps=$nsteps \
			--nensembles=1 \
			--number=$number \
			--nlevels=$nlevels \
			--level=$level \
			--nparams=$nparams \
			--config=${tmp_dir}/config.yaml
		)
#			--node-id=$I \
#			--proc-id=$i \
#			$I $i $barrier_ts 2>&1

		[ $? != 0 ] && failed=1 && which_failed="${which_failed}${sep}write" \
			&& sep="; " && log="${log}"${log_sep}"log: $out" && log_sep="\n"
		#prof="${prof}"${prof_sep}$(echo "$out" | grep -e "Profiling" -e "Processor" -e "Timestamp" -e "fdb-hammer - ") && prof_sep="\n"
		prof="${prof}"${prof_sep}$(echo "$out") && prof_sep="\n"
#		hold=0
	fi

	if [ $R -gt 0 ] ; then
	if [ $fdb_list -eq 0 ] ; then
		#out=$($fdb_hammer \
		out=$(taskset -c $pin_proc $fdb_hammer \
			$tmp_dir/sample${osize} \
			--read \
			--class=rd \
			--expver=$expver \
			--nsteps=$nsteps \
			--nensembles=1 \
			--number=$number \
			--nlevels=$nlevels \
			--level=$level \
			--nparams=$nparams \
			--config=${tmp_dir}/config.yaml
		)
#			--node-id=$I \
#			--proc-id=$i \
#			$I $i $barrier_ts 2>&1

		[ $? != 0 ] && failed=1 && which_failed="${which_failed}${sep}read" \
			&& sep="; " && log="${log}"${log_sep}"log: $out" && log_sep="\n"
		#prof="${prof}"${prof_sep}$(echo "$out" | grep -e "Profiling" -e "Processor" -e "Timestamp" -e "fdb-hammer - ") && prof_sep="\n"
		prof="${prof}"${prof_sep}$(echo "$out") && prof_sep="\n"
#		hold=0
	else
# TODO: if ndatabases > 1, --expver should receive all expver names used by writer processes
#		out=$(taskset -c $pin_proc $fdb_hammer \
#			$tmp_dir/sample${osize} \
#			--list \
#			--class=rd \
#			--expver=$expver \
#			--nsteps=$nsteps \
#			--nensembles=1 \
#			--number=$number \
#			--nlevels=$nlevels \
#			--level=$level \
#			--nparams=$nparams \
#			--config=${tmp_dir}/config.yaml
#		)
		#out=$($fdb_hammer \
		out=$(taskset -c $pin_proc $fdb_hammer \
			$tmp_dir/sample${osize} \
			--list \
			--class=rd \
			--expver=$expver \
			--nsteps=1 \
			--nensembles=$nmembers \
			--number=1 \
			--nlevels=$(( nlevels * procs_per_db )) \
			--level=1 \
			--nparams=$nparams \
			--config=${tmp_dir}/config.yaml
		)
#			--node-id=$I \
#			--proc-id=$i \
#			$I $i $barrier_ts 2>&1

		[ $? != 0 ] && failed=1 && which_failed="${which_failed}${sep}list" \
			&& sep="; " && log="${log}"${log_sep}"log: $out" && log_sep="\n"
		#prof="${prof}"${prof_sep}$(echo "$out" | grep -e "Profiling" -e "Processor" -e "Timestamp" -e "fdb-hammer - ") && prof_sep="\n"
		prof="${prof}"${prof_sep}$(echo "$out") && prof_sep="\n"
#		hold=0
	fi
	fi

	[ $failed -ne 0 ] && echo "Node $I client $i failed at: $which_failed" \
		&& echo -e "${log}" && echo -e "${prof}" && return

	local client_end=`date +%s`
	local client_wc_time=$((client_end-client_start))

	echo -e "Node $I client $i succeeded\n${prof}"
	echo "Profiling node $I client $i - total wc time: $client_wc_time"
}

test_src_dir=$HOME/daos-tests/google/daos/fdb_hammer

if [[ "$backend" == "daos" ]] ; then
    cp $test_src_dir/schema $tmp_dir/schema
    cp $test_src_dir/config.yaml.in $tmp_dir/config.yaml
    sed -i -e "s#@SCHEMA_PATH@#${tmp_dir}/schema#" $tmp_dir/config.yaml
    sed -i -e "s#@POOL@#${pool_id}#" $tmp_dir/config.yaml
    sed -i -e "s#@CONTAINER@#${cont_id}#" $tmp_dir/config.yaml
else
    cp $test_src_dir/schema_posix $tmp_dir/schema
    cp $test_src_dir/config_posix.yaml.in $tmp_dir/config.yaml
    cp $test_src_dir/roots.in $tmp_dir/roots
    cp $test_src_dir/spaces.in $tmp_dir/spaces
    sed -i -e "s#@SCHEMA_PATH@#${tmp_dir}/schema#" $tmp_dir/config.yaml
    sed -i -e "s#@ROOT@#${fdb_root}#" $tmp_dir/roots
    export FDB_ROOT_DIRECTORY=${fdb_root}
    export FDB_ROOTS_FILE=${tmp_dir}/roots
    export FDB_SPACES_FILE=${tmp_dir}/spaces
    #export FDB_DATA_LUSTRE_STRIPE_COUNT=24
fi

export FDB_SCHEMA_FILE=${tmp_dir}/schema

[ ! -e $test_src_dir/sample${osize} ] && \
	echo "sample${osize}.grib not found" && exit 1
cp $test_src_dir/sample${osize} $tmp_dir/sample${osize}
# expected keys:
#stream=oper
#type=fc
#levtype=ml

end=`date +%s`

setup_time=$((end-start))

start=`date +%s`

procs_to_run=$N
[ "$fdb_list" -eq 1 ] && procs_to_run=1

for i in $(seq 0 $((procs_to_run - 1))) ; do
	client $i &
done

wait

end=`date +%s`

wc_time=$((end-start))

start=`date +%s`

cd
rm -rf $tmp_dir

end=`date +%s`

teardown_time=$((end-start))

echo "Profiling node $I - test_field_io setup wc time: $setup_time"
echo "Profiling node $I - test_field_io all clients wc time: $wc_time"
echo "Profiling node $I - test_field_io teardown wc time: $teardown_time"
