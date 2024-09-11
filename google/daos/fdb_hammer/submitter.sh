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

#!/bin/env bash

# USAGE: ./fdb_hammer/submitter.sh <N_CLIENT_NODES> <FDB_HAMMER_TEST_SCRIPT_NAME> <SCRIPT_ARGS>

if [ ! -e fdb_hammer/test_wrapper.sh ] ; then
	echo "./fdb_hammer/test_wrapper.sh not found. Please cd to daos-tests/google/daos"
fi

list=false

args=("$@")
sep=
arg_string=
for arg in "${args[@]}" ; do
	arg_string=${arg_string}${sep}${arg}
	sep="_"
    [ "$arg" == "--list" ] || [ "$arg" == "-L" ] && list=true 
done

n_nodes=$1
shift

forward_args=("$@")
forward_args+=("--num-nodes" "$n_nodes")

[[ "$list" == "true" ]] && n_nodes=1

mkdir -p runs

script_filename="runs/fdb_hammer_$arg_string".sh

cat > $script_filename <<EOF
#!/bin/env bash

#SBATCH --ntasks=${n_nodes}

#SBATCH --job-name="fdb_hammer_$arg_string"
#SBATCH --output=runs/fdb_hammer_${arg_string}.out
#SBATCH --error=runs/fdb_hammer_${arg_string}.err

#SBATCH --cpus-per-task=32
#SBATCH --time=00:40:00

srun fdb_hammer/test_wrapper.sh ${forward_args[@]}
EOF

sbatch_args=( "-N${n_nodes}" "$script_filename" )

sbatch "${sbatch_args[@]}"
