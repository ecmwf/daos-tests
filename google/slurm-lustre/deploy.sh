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
