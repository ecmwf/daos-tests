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

# assumes hpc-toolkit is installed in $HOME
# last tested with hpc-toolkit v1.34.0

export PROJECT_ID=< INSERT GCP PROJECT ID >



# build ceph images

deploy_path=$HOME/gcp-deployments
mkdir $deploy_path
cd $deploy_path

envsubst < ceph-build.yaml.in > ceph-build.yaml

$HOME/hpc-toolkit/ghpc create ${deploy_path}/ceph-build.yaml  \
  --vars project_id=${PROJECT_ID?}

$HOME/hpc-toolkit/ghpc deploy ceph-build
# confirm when prompted

$HOME/hpc-toolkit/ghpc destroy ceph-build --auto-approve



# deploy ceph

deploy_path=$HOME/gcp-deployments
mkdir $deploy_path
cd $deploy_path

ssh_user=cephadm-user
[ ! -f ./id_rsa_ceph ] && ssh-keygen -t rsa -b 4096 -C "${ssh_user}" -N '' -f ./id_rsa_ceph
chmod 600 ./id_rsa_ceph

# at this point the clinet slurm cluster in daos-tests/google/slurm must be deployed
# the ssh key generated above here must be used as input for the slurm blueprint

nnodes=16

create_node_template() {

  gcloud compute instance-templates delete mystore-template --quiet \
    --project=${PROJECT_ID?}
  [ $? -ne 0 ] && echo "WARNING: Instance template deletion failed!"

  cd ${deploy_path?}

  cat > startup-script_ceph_storage_node << EOF
adduser ${ssh_user?}
chmod u+w /etc/sudoers
echo '${ssh_user} ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
chmod u-w /etc/sudoers
mkdir -p /home/${ssh_user}/.ssh
EOF

  [ ! -f ./id_rsa_ceph.pub ] && echo "WARNING: ssh key not found" && return 1
  echo "${ssh_user}:$(cat ./id_rsa_ceph.pub)" > ./keys_ceph.txt

  gcloud compute instance-templates create mystore-template \
    --project=${PROJECT_ID?} \
    --region=us-central1 \
    --machine-type=n2-custom-36-153600 \
    --local-ssd=device-name=ssd1,interface=nvme \
    --local-ssd=device-name=ssd2,interface=nvme \
    --local-ssd=device-name=ssd3,interface=nvme \
    --local-ssd=device-name=ssd4,interface=nvme \
    --local-ssd=device-name=ssd5,interface=nvme \
    --local-ssd=device-name=ssd6,interface=nvme \
    --local-ssd=device-name=ssd7,interface=nvme \
    --local-ssd=device-name=ssd8,interface=nvme \
    --local-ssd=device-name=ssd9,interface=nvme \
    --local-ssd=device-name=ssd10,interface=nvme  \
    --local-ssd=device-name=ssd11,interface=nvme  \
    --local-ssd=device-name=ssd12,interface=nvme  \
    --local-ssd=device-name=ssd13,interface=nvme  \
    --local-ssd=device-name=ssd14,interface=nvme  \
    --local-ssd=device-name=ssd15,interface=nvme  \
    --local-ssd=device-name=ssd16,interface=nvme  \
    --network-interface=stack-type=IPV4_ONLY,subnet=${NETWORK_NAME},nic-type=GVNIC \
    --network-performance-configs=total-egress-bandwidth-tier=TIER_1 \
    --create-disk=auto-delete=yes,boot=yes,device-name=client-vm1,image=< INSERT YOUR BUILT IMAGE ID >,mode=rw,size=20,type=pd-balanced \
    --metadata-from-file=ssh-keys=${deploy_path}/keys_ceph.txt \
    --metadata-from-file=startup-script=${deploy_path}/startup-script_ceph_storage_node \
    --provisioning-model=SPOT

  [ $? -ne 0 ] && echo "WARNING: Instance template deletion failed!" && return 1

  return 0

}

create_storage_nodes() {

  local nnodes=$1

  local out=$(gcloud compute instances bulk create --name-pattern="mystore-##" \
    --count $nnodes \
    --project=${PROJECT_ID?} \
    --zone=us-central1-a \
    --source-instance-template=mystore-template 2>&1)

  local code=$?

  echo "${out}" | grep -q "ERROR"

  [ $? -eq 0 ] || [ $code -ne 0 ] && echo "WARNING: storage instance creation failed!" && return 1

  return 0

}

create() {

  local nnodes=$1

  create_node_template
  [ $? -ne 0 ] && return 1

  create_storage_nodes $nnodes
  [ $? -ne 0 ] && return 1

  local listout=$(gcloud compute instances list --project=${PROJECT_ID?})
  [ $? -ne 0 ] && "WARNING: storage instance list failed!" && return 1
  local storage_node_names=($(
    echo "${listout}" | \
      grep -e '^mystore-[0-9]\+ ' | \
      awk '{print $1}'
  ))
  local storage_node_ips=($(
    echo "${listout}" | \
      grep -e '^mystore-[0-9]\+ ' | \
      awk '{print $10}'
  ))
  local slurm_node_name=hpcslurm-controller
  local slurm_node_ip=$(
    echo "${listout}" | \
      grep -e '^hpcslurm-controller ' | \
      awk '{print $5}'
  )

  cd ${deploy_path?}

  [ ! -f ./id_rsa_ceph ] && "Unexpected condition" && return 1
  [ ! -f ./keys_ceph.txt ] && "Unexpected condition" && return 1

  cat > startup-script_ceph << EOF

storage_node_names=( ${storage_node_names[@]} )
storage_node_ips=( ${storage_node_ips[@]} )

adduser ${ssh_user?}
sudoers_file=/etc/sudoers
chmod u+w \${sudoers_file}
echo '${ssh_user} ALL=(ALL) NOPASSWD: ALL' >> \${sudoers_file}
chmod u-w \${sudoers_file}
mkdir -p /home/${ssh_user}/.ssh
echo '$( cat ./id_rsa_ceph )' > /home/${ssh_user}/.ssh/id_rsa_ceph
echo '$( cat ./id_rsa_ceph.pub )' > /home/${ssh_user}/.ssh/id_rsa_ceph.pub
chmod 600 /home/${ssh_user}/.ssh/id_rsa_ceph
chmod 644 /home/${ssh_user}/.ssh/id_rsa_ceph.pub

MANAGER_IP=\$(ifconfig | grep eth0 -A1 | grep 'inet ' | awk '{print \$2}')

cephadm bootstrap \
  --mon-ip \${MANAGER_IP} \
  --log-to-file \
  --cleanup-on-failure \
  --ssh-user ${ssh_user?} \
  --ssh-private-key /home/${ssh_user}/.ssh/id_rsa_ceph \
  --ssh-public-key /home/${ssh_user}/.ssh/id_rsa_ceph.pub

ceph orch apply mon --unmanaged
ceph config set mon mon_allow_pool_delete true
ceph config set global mon_allow_pool_size_one true
ceph config set global osd_pool_default_pg_autoscale_mode off

for i in \$( seq 0 \$(( \${#storage_node_names[@]} - 1 )) ) ; do
  #ssh-copy-id -f -i /etc/ceph/ceph.pub ${ssh_user}@\${node}
  failed=1
  attempts=0
  while [ \$failed -eq 1 ] ; do
    out=\$(ceph orch host add \${storage_node_names[\$i]} \${storage_node_ips[\$i]} 2>&1)
    echo "\${out}"
    echo "\${out}" | grep -q "Error"
    if [ \$? -ne 0 ] ; then
      failed=0
    else
      attempts=\$(( attempts + 1 ))
      [[ \$attempts -gt 20 ]] && shutdown -h now
      sleep 5
    fi
  done
done

ceph orch host add ${slurm_node_name} ${slurm_node_ip} --labels=_no_schedule,_admin

ceph orch apply osd --all-available-devices
EOF

  local out=$(gcloud compute instances create mystore-manager \
    --project=${PROJECT_ID?} \
    --zone=us-central1-a \
    --machine-type=c2-standard-4 \
    --network-interface=stack-type=IPV4_ONLY,subnet=${NETWORK_NAME},nic-type=GVNIC \
    --network-performance-configs=total-egress-bandwidth-tier=DEFAULT \
    --create-disk=auto-delete=yes,boot=yes,device-name=mystore-manager,image=< INSERT YOUR BUILT IMAGE ID >,mode=rw,size=20,type=pd-balanced \
    --metadata-from-file=ssh-keys=${deploy_path}/keys_ceph.txt \
    --metadata-from-file=startup-script=${deploy_path}/startup-script_ceph \
    --provisioning-model=SPOT 2>&1)

    #--async \

  local code=$?

  echo "${out}" | grep -q "ERROR"

  [ $? -eq 0 ] || [ $code -ne 0 ] && echo "WARNING: Instance mystore-manager provisioning failed!" && return 1
  #sleep 5

  return 0

}


delete() {

  local out=$(gcloud compute instances list --project=${PROJECT_ID?})
  local code=$?
  [ "$code" -ne 0 ] && echo "WARNING: Instance list failed!" && return 1

  local instances_to_delete=( $( echo "${out}" | grep -e 'mystore-' | awk '{print $1}' ) )

  [ "${#instances_to_delete[@]}" -eq 0 ] && return 0

  gcloud compute instances delete "${instances_to_delete[@]}" --quiet \
    --project=${PROJECT_ID?} \
    --zone=us-central1-a
  [ $? -ne 0 ] && echo "WARNING: Instance $name delete failed!" && return 1
  sleep 10  # for local ssd quotas to refresh before further creating

  return 0

}

while [ 1 ] ; do

  echo "Checking for evicted mystore instances..."

  out=$(gcloud compute instances list --project=${PROJECT_ID?})
  code=$?
  [ "$code" -ne 0 ] && echo "WARNING: Instance list failed!" && continue

  nfound=$(echo "${out}" | grep -e "^mystore-[0-9]\+ " | wc -l)
  n_manager_found=$(echo "${out}" | grep -e 'mystore-manager' | wc -l)

  echo "${out}" | grep -q -e "^mystore-.* TERMINATED"

  # if no instances are terminated and the total number of instances matches the target,
  # the full cluster is up and nothing has to be done
  [ $? -ne 0 ] && [ "$nfound" -eq "$nnodes" ] && [ "$n_manager_found" -eq 1 ] && \
    echo "Sleeping..." && sleep 10 && continue

  echo "Deleting instances..."

  delete
  [ $? -ne 0 ] && continue

  echo "Waiting for slurm controller to be ready..."

  ready=0
  while [ ! $ready ] ; do
    gcloud compute ssh hpcslurm-controller --zone=us-central1-a --project=${PROJECT_ID?} -- \
      'sudo tail -n 1 /slurm/scripts/setup.log' | \
      grep -q "Done setting up controller"
    [ $? -eq 0 ] && ready=1 && continue
    sleep 10
  done

  echo "Reprovisioning..."

  create $nnodes
  [ $? -ne 0 ] && echo "Creation failed. Sleeping..." && sleep 30 && continue

  echo "Ceph deployed."

done



# troubleshooting:

#gcloud compute ssh cephadm-user@mystore-manager --zone=us-central1-a --project=${PROJECT_ID?} --ssh-key-file=${deploy_path}/id_rsa_ceph

#sudo journalctl -u google-startup-scripts.service

#sudo ceph config show osd.0 | grep osd_max_object_size
