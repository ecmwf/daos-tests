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
export NETWORK_NAME=< INSTER GCP NETWORK NAME LUSTRE IS BOUND TO >



# build slurm images

deploy_path=$HOME/gcp-deployments
mkdir $deploy_path
cd $deploy_path

export LUSTRE_USER=lustre-user

envsubst < slurm-lustre-build.yaml.in > slurm-lustre-build.yaml

$HOME/hpc-toolkit/ghpc create ${deploy_path}/slurm-lustre-build.yaml  \
  --vars project_id=${PROJECT_ID?}

$HOME/hpc-toolkit/ghpc deploy slurm-lustre-build
# confirm when prompted

$HOME/hpc-toolkit/ghpc destroy slurm-lustre-build --auto-approve



# create home NFS

gcloud filestore instances create slurm-home \
  --file-share=name=home,capacity=1TB --network=name=${NETWORK_NAME} --tier=BASIC_HDD \
  --location us-central1-a --project ${PROJECT_ID?}

export NFS_IP=$( \
  gcloud filestore instances describe slurm-home \
  --project=$PROJECT_ID --location us-central1-a \
  --format "value[delimiter=','](format("{0}", networks[0].ipAddresses[0]))" )



# deploy slurm

export ACCESS_POINTS=< INSERT DAOS ACCESS POINT IPs ['ip1', 'ip2', ...] >

export LUSTRE_USER=lustre-user

cd $deploy_path

[ ! -f ./id_rsa_lustre ] && ssh-keygen -t rsa -b 4096 -C "${LUSTRE_USER}" -N '' -f ./id_rsa_lustre
chmod 600 ./id_rsa_lustre

export LUSTRE_SSH_PUB_KEY=$(cat ./id_rsa_lustre.pub)

envsubst < hpc-slurm-lustre.yaml.in > hpc-slurm-lustre.yaml

$HOME/hpc-toolkit/ghpc create ${deploy_path}/hpc-slurm-lustre.yaml  \
  --vars project_id=${PROJECT_ID?}

$HOME/hpc-toolkit/ghpc deploy hpc-slurm-lustre
# cancel when prompted

grep -rl 'setup_nss_slurm()$' hpc-slurm-lustre/* | \
  xargs sed -i -e 's/setup_nss_slurm()$/#setup_nss_slurm()/g'

$HOME/hpc-toolkit/ghpc deploy hpc-slurm-lustre



# troubleshooting

#gcloud compute ssh hpcslurmlu-controller --zone=us-central1-a --project=${PROJECT_ID?}

#sudo cat /slurm/scripts/setup.log

#srun -N 1 hostname

#gcloud compute ssh hpcslurmlu-computenodeset-0 --zone=us-central1-a --project=${PROJECT_ID?}

#sudo cat /slurm/scripts/setup.log
