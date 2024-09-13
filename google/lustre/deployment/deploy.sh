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



# build lustre images

deploy_path=$HOME/gcp-deployments
mkdir $deploy_path
cd $deploy_path

export DAOS_USER=daos-user
export LUSTRE_USER=lustre-user

envsubst < lustre-build.yaml.in > lustre-build.yaml

$HOME/hpc-toolkit/ghpc create ${deploy_path}/lustre-build.yaml  \
  --vars project_id=${PROJECT_ID?}

$HOME/hpc-toolkit/ghpc deploy lustre-build
# confirm when prompted

$HOME/hpc-toolkit/ghpc destroy lustre-build --auto-approve



# deploy lustre

deploy_path=$HOME/gcp-deployments
mkdir $deploy_path
cd $deploy_path

ssh_user=lustreadm-user
[ ! -f ./id_rsa_lustre ] && ssh-keygen -t rsa -b 4096 -C "${ssh_user}" -N '' -f ./id_rsa_lustre
chmod 600 ./id_rsa_lustre

nnodes=16

create_node_template() {

  gcloud compute instance-templates delete mystore-template --quiet \
    --project=${PROJECT_ID?}
  [ $? -ne 0 ] && echo "WARNING: Instance template deletion failed!"

  cd ${deploy_path?}

  cat > startup-script_lustre_storage_node << EOF
adduser ${ssh_user?}
chmod u+w /etc/sudoers
echo '${ssh_user} ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
chmod u-w /etc/sudoers
mkdir -p /home/${ssh_user}/.ssh

modprobe -v lustre
modprobe -v lnet

mgs_avail=0
while [ \$mgs_avail -eq 0 ] ; do
  mgs_avail=\$(getent ahostsv4 mystore-manager | wc -l)
  [ \$mgs_avail -eq 0 ] && echo "Waiting for mdt to be available..." && sleep 10
done

mgsip="\$(getent ahostsv4 mystore-manager | grep RAW | awk '{print \$1}')@tcp"
hn=\$(hostname)
nid=\$((10#\${hn##*-}))

pids=()
for i in \`seq 1 16\` ; do
  mkfs.lustre --reformat --ost --fsname=newlust --mgsnode=\${mgsip} --index=\$(( (16 * (nid - 1)) + i - 1)) --mkfsoptions='-t ext4' /dev/nvme0n\${i} &
  pids+=(\$!)
done

for pid in "\${pids[@]}" ; do
  wait \$pid
done

for i in \`seq 1 16\` ; do
  mkdir /ost\$(( i - 1 ))
  rc=1
  while [ \$rc -ne 0 ] ; do
    timeout 2 mount -t lustre /dev/nvme0n\${i} /ost\$(( i - 1 ))
    rc=\$?
    [ \$rc -ne 0 ] && echo "Waiting for mdt to be available..." && sleep 10
  done
done
EOF

  [ ! -f ./id_rsa_lustre.pub ] && echo "WARNING: ssh key not found" && return 1
  echo "${ssh_user}:$(cat ./id_rsa_lustre.pub)" > ./keys_lustre.txt

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
    --metadata-from-file=ssh-keys=${deploy_path}/keys_lustre.txt \
    --metadata-from-file=startup-script=${deploy_path}/startup-script_lustre_storage_node \
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

  [ $? -eq 0 ] || [ $code -ne 0 ] && echo "WARNING: storage instance creation failed!" && echo "${out}" && return 1

  return 0

}

create() {

  local nnodes=$1

  create_node_template
  [ $? -ne 0 ] && return 1

  create_storage_nodes $nnodes
  [ $? -ne 0 ] && return 1

  cd ${deploy_path?}

  [ ! -f ./id_rsa_lustre ] && "Unexpected condition" && return 1
  [ ! -f ./keys_lustre.txt ] && "Unexpected condition" && return 1

  cat > startup-script_lustre << EOF
adduser ${ssh_user?}
sudoers_file=/etc/sudoers
chmod u+w \${sudoers_file}
echo '${ssh_user} ALL=(ALL) NOPASSWD: ALL' >> \${sudoers_file}
chmod u-w \${sudoers_file}
mkdir -p /home/${ssh_user}/.ssh
echo '$( cat ./id_rsa_lustre )' > /home/${ssh_user}/.ssh/id_rsa_lustre
echo '$( cat ./id_rsa_lustre.pub )' > /home/${ssh_user}/.ssh/id_rsa_lustre.pub
chmod 600 /home/${ssh_user}/.ssh/id_rsa_lustre
chmod 644 /home/${ssh_user}/.ssh/id_rsa_lustre.pub

modprobe -v lustre
modprobe -v lnet
mgsip=\$(lnetctl net show | grep 'type: tcp' -A2 | tail -n 1 | awk '{print \$3}')

pids=()
#for i in \`seq 1 16\` ; do
for i in \`seq 1 1\` ; do
  if [ \$i -eq 1 ] ; then
    mkfs.lustre --reformat --fsname=newlust --mgs --mdt --index=\$(( i - 1 )) /dev/nvme0n\${i} &
  else
    mkfs.lustre --reformat --fsname=newlust --mgsnode=\${mgsip} --mdt --index=\$(( i - 1 )) /dev/nvme0n\${i} &
  fi
  pids+=(\$!)
done

for pid in "\${pids[@]}" ; do
  wait \$pid
done

#for i in \`seq 1 16\` ; do
for i in \`seq 1 1\` ; do
  mkdir /mdt\$(( i - 1 ))
  mount -t lustre /dev/nvme0n\${i} /mdt\$(( i - 1 ))
done
EOF

  local out=$(gcloud compute instances create mystore-manager \
    --project=${PROJECT_ID?} \
    --zone=us-central1-a \
    --machine-type=n2-custom-36-153600 \
    --local-ssd=device-name=ssd1,interface=nvme \
    --local-ssd=device-name=ssd2,interface=nvme \
    --local-ssd=device-name=ssd3,interface=nvme \
    --local-ssd=device-name=ssd4,interface=nvme \
    --network-interface=stack-type=IPV4_ONLY,subnet=${NETWORK_NAME},nic-type=GVNIC \
    --network-performance-configs=total-egress-bandwidth-tier=TIER_1 \
    --create-disk=auto-delete=yes,boot=yes,device-name=client-vm1,image=< INSERT YOUR BUILT IMAGE ID >,mode=rw,size=20,type=pd-balanced \
    --metadata-from-file=ssh-keys=${deploy_path}/keys_lustre.txt \
    --metadata-from-file=startup-script=${deploy_path}/startup-script_lustre \
    --provisioning-model=SPOT 2>&1)

    #--async \

  local code=$?

  echo "${out}" | grep -q "ERROR"

  [ $? -eq 0 ] || [ $code -ne 0 ] && echo "WARNING: Instance mystore-manager provisioning failed!" && echo "${out}" && return 1
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

  echo "Reprovisioning..."

  create $nnodes
  [ $? -ne 0 ] && echo "Creation failed. Sleeping..." && sleep 30 && continue

  echo "Lustre deployed."

done



# troubleshooting

#gcloud compute ssh lustreadm-user@mystore-manager --zone=us-central1-a --project=${PROJECT_ID?} --ssh-key-file=${deploy_path}/id_rsa_lustre

#sudo journalctl -u google-startup-scripts.service
