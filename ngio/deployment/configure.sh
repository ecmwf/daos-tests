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
#cns=("nextgenio-cn28")
# 2
cns=("nextgenio-cn28" "nextgenio-cn29")
# 4
#cns=("nextgenio-cn28" "nextgenio-cn29" "nextgenio-cn20" "nextgenio-cn21")
# 8
#cns=("nextgenio-cn28" "nextgenio-cn29" "nextgenio-cn20" "nextgenio-cn21" "nextgenio-cn22" "nextgenio-cn23" "nextgenio-cn24" "nextgenio-cn25")
# 10
#cns=("nextgenio-cn28" "nextgenio-cn29" "nextgenio-cn20" "nextgenio-cn21" "nextgenio-cn22" "nextgenio-cn23" "nextgenio-cn24" "nextgenio-cn25" "nextgenio-cn26" "nextgenio-cn27")
# 12
#cns=("nextgenio-cn28" "nextgenio-cn29" "nextgenio-cn20" "nextgenio-cn21" "nextgenio-cn22" "nextgenio-cn23" "nextgenio-cn24" "nextgenio-cn25" "nextgenio-cn26" "nextgenio-cn27" "nextgenio-cn06" "nextgenio-cn07")
# 14
#cns=("nextgenio-cn28" "nextgenio-cn29" "nextgenio-cn20" "nextgenio-cn21" "nextgenio-cn22" "nextgenio-cn23" "nextgenio-cn24" "nextgenio-cn25" "nextgenio-cn26" "nextgenio-cn27" "nextgenio-cn06" "nextgenio-cn07" "nextgenio-cn08" "nextgenio-cn09")
# 16
#cns=("nextgenio-cn28" "nextgenio-cn29" "nextgenio-cn20" "nextgenio-cn21" "nextgenio-cn22" "nextgenio-cn23" "nextgenio-cn24" "nextgenio-cn25" "nextgenio-cn26" "nextgenio-cn27" "nextgenio-cn06" "nextgenio-cn07" "nextgenio-cn08" "nextgenio-cn09" "nextgenio-cn31" "nextgenio-cn32")
cd
for cn in "${cns[@]}" ; do
    ssh -t $cn 'mkdir -p /tmp/daos-tests'
    rsync -a --exclude 'ngio/runs' daos-tests/ ${cn}:/tmp/daos-tests --chmod=D777,F777
done

