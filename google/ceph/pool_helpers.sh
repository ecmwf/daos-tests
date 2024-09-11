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

function create_pool_cont {

local posix_cont=$1
local on_posix=$2
local servers=$3
local test_name=${4:-field_io}  # either fdb_hammer or field_io
local dfs_oclass=${5:-S1}

local code=0

    local server_nodes=
    local osds_per_node=16
    local best_pg=

    # best amount of pgs is determined as osds*100/replicas rounded to the closest power of 2
    # because the default number of replicas before readjusting is 3 and the maximum pgs per osd is 250,
    # using this amount directly exceeds maximum pgs allowed.
    # Therefore the lower power of 2 is used in most cases.

    #[[ "$servers" == "single_server" ]] && server_nodes=1 && best_pg=1024
    #[[ "$servers" == "quad_server" ]] && server_nodes=4 && best_pg=4096
    #[[ "$servers" == "octa_server" ]] && server_nodes=8 && best_pg=8192
    #[[ "$servers" == "twelve_server" ]] && server_nodes=12 && best_pg=8192
    #[[ "$servers" == "sixteen_server" ]] && server_nodes=16 && best_pg=16384
    #[[ "$servers" == "twenty_server" ]] && server_nodes=20 && best_pg=16384
    #[[ "$servers" == "twentyfour_server" ]] && server_nodes=24 && best_pg=16384

    # however, the ideal pg is experimentally found to be even one step lower
    [[ "$servers" == "single_server" ]] && server_nodes=1 && best_pg=512
    [[ "$servers" == "dual_server" ]] && server_nodes=2 && best_pg=1024
    [[ "$servers" == "quad_server" ]] && server_nodes=4 && best_pg=2048
    [[ "$servers" == "octa_server" ]] && server_nodes=8 && best_pg=4096
    [[ "$servers" == "twelve_server" ]] && server_nodes=12 && best_pg=4096
    [[ "$servers" == "sixteen_server" ]] && server_nodes=16 && best_pg=8192
    [[ "$servers" == "twenty_server" ]] && server_nodes=20 && best_pg=8192
    [[ "$servers" == "twentyfour_server" ]] && server_nodes=24 && best_pg=8192

    local pool="default-pool-${best_pg}-pg-1-1-rep"
    
    local namespace=$(od -An -N3 -i /dev/random)

    local total_osds=$(( server_nodes * osds_per_node ))
    local status=
    local ready=0
    local osds_ready=
    local service_ready=
    while [ $ready -eq 0 ] ; do
      echo "Waiting for Ceph to be ready..."
      status=$(sudo timeout 3 ceph -s)
      echo "${status}" | grep -q "osd: ${total_osds} osds: ${total_osds} up"
      osds_ready=$?
      echo "${status}" | grep -q -e 'health: HEALTH_OK'
      service_ready=$?
      [ $osds_ready -eq 0 ] && [ $service_ready -eq 0 ] && ready=1 && continue
      sleep 5
    done

    # copy configuration from /etc on controller node onto home (in nfs) for 
    # compute nodes to see it
    mkdir -p $HOME/.ceph
    sudo cat /etc/ceph/ceph.conf > $HOME/.ceph/ceph.conf
    sudo cat /etc/ceph/ceph.client.admin.keyring > $HOME/.ceph/ceph.client.admin.keyring
    cat >> $HOME/.ceph/ceph.conf << EOF
[client]
        keyring = $HOME/.ceph/ceph.client.admin.keyring
EOF

    replicas=1
    sudo ceph osd pool create ${pool} $best_pg $best_pg replicated
    [ $? -ne 0 ] && echo "Pool create failed" && code=1
    sudo ceph osd pool set ${pool} min_size $replicas
    sudo ceph osd pool set ${pool} size $replicas --yes-i-really-mean-it

    echo "POOL: $pool"
    echo "CONT: $namespace"

    return $code

}

function destroy_pool_cont {

local on_posix=$1
local servers=$2
local test_name=${3:-field_io}

local code=0

local server_nodes=
local osds_per_node=16
local best_pg=

[[ "$servers" == "single_server" ]] && server_nodes=1 && best_pg=512
[[ "$servers" == "quad_server" ]] && server_nodes=4 && best_pg=2048
[[ "$servers" == "octa_server" ]] && server_nodes=8 && best_pg=4096
[[ "$servers" == "twelve_server" ]] && server_nodes=12 && best_pg=4096
[[ "$servers" == "sixteen_server" ]] && server_nodes=16 && best_pg=8192
[[ "$servers" == "twenty_server" ]] && server_nodes=20 && best_pg=8192
[[ "$servers" == "twentyfour_server" ]] && server_nodes=24 && best_pg=8192

local pool="default-pool-${best_pg}-pg-1-1-rep"

local ready=0
local service_ready=
local status=0
while [ $ready -eq 0 ] ; do
  echo "Waiting for Ceph to be ready..."
  status=$(sudo timeout 3 ceph -s)
  echo "${status}" | tr '\r\n' '_' | grep -q -e 'health: HEALTH_WARN_ *1 pool(s).*_ *1 pool(s).*_ *_  services:' -e 'health: HEALTH_OK'
  service_ready=$?
  [ $service_ready -eq 0 ] && ready=1 && continue
  sleep 5
done

local npools=$(sudo ceph osd pool ls | wc -l)
if [ $npools -gt 1 ] ; then
  sudo ceph osd pool rm ${pool} ${pool} --yes-i-really-really-mean-it
  [ $? -ne 0 ] && echo "Pool destroy failed" && code=1
fi

return $code

}
