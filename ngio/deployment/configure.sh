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

# 1
#cns=("nextgenio-cn01")
# 2
#cns=("nextgenio-cn01" "nextgenio-cn02")
# 4
#cns=("nextgenio-cn01" "nextgenio-cn02" "nextgenio-cn03" "nextgenio-cn04")
# 8
#cns=("nextgenio-cn01" "nextgenio-cn02" "nextgenio-cn03" "nextgenio-cn04" "nextgenio-cn05" "nextgenio-cn06" "nextgenio-cn07" "nextgenio-cn08")
# 10
cns=("nextgenio-cn01" "nextgenio-cn02" "nextgenio-cn03" "nextgenio-cn04" "nextgenio-cn05" "nextgenio-cn06" "nextgenio-cn07" "nextgenio-cn08" "nextgenio-cn09" "nextgenio-cn10")
# 12
#cns=("nextgenio-cn01" "nextgenio-cn02" "nextgenio-cn03" "nextgenio-cn04" "nextgenio-cn05" "nextgenio-cn06" "nextgenio-cn07" "nextgenio-cn08" "nextgenio-cn09" "nextgenio-cn10" "nextgenio-cn11" "nextgenio-cn12")
# 14
#cns=("nextgenio-cn01" "nextgenio-cn02" "nextgenio-cn03" "nextgenio-cn04" "nextgenio-cn05" "nextgenio-cn06" "nextgenio-cn07" "nextgenio-cn08" "nextgenio-cn09" "nextgenio-cn10" "nextgenio-cn11" "nextgenio-cn12" "nextgenio-cn13" "nextgenio-cn14")
# 16
#cns=("nextgenio-cn01" "nextgenio-cn02" "nextgenio-cn03" "nextgenio-cn04" "nextgenio-cn05" "nextgenio-cn06" "nextgenio-cn07" "nextgenio-cn08" "nextgenio-cn09" "nextgenio-cn10" "nextgenio-cn11" "nextgenio-cn12" "nextgenio-cn13" "nextgenio-cn14" "nextgenio-cn15" "nextgenio-cn16")
cd
for cn in "${cns[@]}" ; do
    ssh -t $cn 'mkdir -p /tmp/daos-tests'
    rsync -a --exclude 'ngio/runs' daos-tests/ ${cn}:/tmp/daos-tests --chmod=D777,F777
done

