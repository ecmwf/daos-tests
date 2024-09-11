# DAOS, Ceph and Lustre performance tests on GCP

The following steps need to be followed to execute this artifact.

- Obtain a Google Cloud Platform account.

- Install Google Cloud SDK (last tested with v488.0.0), go (last tested with v1.22.1), Terraform (last tested with v1.9.4) and hpc-toolkit (last tested with v1.38.0).

- Clone this artifact.

- Run the scripts to provision the different storage systems (one at a time) and the Slurm client cluster, available in the artifact under `google/ceph/deployment/deploy.sh`, `google/lustre/deployment/deploy.sh`, and `google/slurm/deploy.sh`, respectively.

- Open an ssh connection to the Slurm controller node with `gcloud compute ssh`.
    
- Clone this artifact under `$HOME/daos-tests` in the controller node.
    
- Locate the master test script, in function of the storage system and benchmark to be tested, available in the artifact under `google/<storage system>/<benchmark>/access_patterns/A.sh`.

- Adjust the master test script with the amounts of server nodes (specified in the `servers` variable), client nodes (specified as a vector via the `C` variable) and processes per client node (specified as a vector via the `N` variable) to test with. The amount of I/O iterations per process and test repetitions can also be adjusted (via the variables `WR` and `REP`), but are generally set to 10k and 3 by default, respectively. For IOR tests, the IOR APIs to test with can also be adjusted via the `API` variable. For DAOS tests, the object class can be adjusted via the `OC` variable.

- Change directories to the `google/<storage system>` directory, and invoke the master script with `source <benchmark>/access_patterns/A.sh`.

- When executed, a master script performs the following tasks:
    - check that the storage system is available
    - spin up the required Slurm client nodes
    - build and/or install the client software if not present
    - execute the benchmark in a loop for all configured client node and process counts, APIs, object classes, and repetitions

- All test output is stored in a directory hierarchy under `google/<storage system>/runs`.
