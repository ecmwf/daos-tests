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

ssh nextgenio-cn28

#export FI_TCP_IFACE=ib0
export FI_TCP_BIND_BEFORE_CONNECT=1
export CRT_PHY_ADDR_STR="ofi+tcp;ofi_rxm"
export FI_PROVIDER=tcp

export FI_TCP_MAX_CONN_RETRY=1
export FI_TCP_CONN_TIMEOUT=2000

export CRT_TIMEOUT=1000
export CRT_CREDIT_EP_CTX=0

export D_LOG_MASK=
export DD_SUBSYST=all
export DD_MASK=all
export DAOS_AGENT_DRPC_DIR=/tmp/daos/run/daos_agent/
export LD_LIBRARY_PATH=/usr/lib64:$LD_LIBRARY_PATH

module load libfabric/latest
export LD_LIBRARY_PATH=/home/software/psm2/11.2.228/usr/lib64:/home/software/libfabric/latest/lib:$LD_LIBRARY_PATH

dmg storage format --reformat -i -o /tmp/daos-tests/ngio/config/daos_control.yaml
