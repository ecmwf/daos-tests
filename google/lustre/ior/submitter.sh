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

# USAGE: ./ior/submitter.sh <N_CLIENT_NODES> <SCRIPT_NAME> <IOR_API> <FABRIC_PROVIDER> <SCRIPT_ARGS>

if [ ! -e ior/test_wrapper.sh ] ; then
	echo "./ior/test_wrapper.sh not found. Please cd to daos-tests/google/lustre"
fi

args=("$@")
sep=
arg_string=
for arg in "${args[@]}" ; do
	arg_string=${arg_string}${sep}${arg}
	sep="_"
done

n_nodes=$1

forward_args=("$@")

mkdir -p runs

script_filename="runs/daos_$arg_string".sh

cat > $script_filename <<EOF
#!/bin/bash

#SBATCH --job-name="daos_$arg_string"
#SBATCH --output=runs/daos_${arg_string}.out
#SBATCH --error=runs/daos_${arg_string}.err

#SBATCH --cpus-per-task=32
#SBATCH --time=00:10:00

srun ior/test_wrapper.sh ${forward_args[@]}
EOF

sbatch_args=( "-N${n_nodes}" "$script_filename" )

sbatch "${sbatch_args[@]}"
