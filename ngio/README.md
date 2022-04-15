# NEXTGenIO performance tests

This documentation summarizes steps followed to conduct performance tests in NEXTGenIO with the IOR and Field I/O benchmarks.

- Request for access and use of the platform via http://www.nextgenio.eu/contact.

- Request for installation of DAOS v2.0.1, following the guidance in https://docs.daos.io/v2.0/QSG/setup_centos/. The `Dockerfile` provided in the `docker` folder may give insight on the software requirements, but there are additional hardware and system configuration steps required.

- Clone this Git project in the login node, under $HOME.

- Install ecbuild under $HOME, and build and install libuuid from util-linux >= 2.32.1 under $HOME/local (see the `docker` folder in this Git repository to see an example).

- Clone IOR 3.3.0rc1 in the login node, under $HOME.

Once the system is ready with DAOS installed and all necessary sources for testing, the benchmarks can be run. For each benchmark run, the following steps have been carried out manually.

- Place a reservation or allocation for as many server nodes as desired for the benchmark run.

- Deploy DAOS on the server nodes by a) adjusting the DAOS configuration files in the `config` folder if necessary, for example to configure the names of the nodes to be used as servers; b) running `configure.sh` on the login node to distribute the adjusted `config` folder and other necessary fixtures to all server nodes (requires some adjustment); c) running the `quick_fire.sh` script on each server node to start DAOS servers; d) running the `format.sh` script from the login node to format the DAOS cluster (requires some adjustment).

- Run the desired access pattern script (with `source field_io/<pattern>.sh` or `source ior/<pattern>.sh`). These scripts automatically call the rest of the scripts in the `ngio` folder: `pool_helpers.sh` is called to create and destroy DAOS pools and containers before/after the runs, and `field_io/submitter.sh` or `ior/submitter.sh` are called to create slurm job reservations for as many client nodes as needed and run `field_io/test_wrapper.sh` or `ior/test_wrapper.sh`, respectively, from all client nodes. When a wrapper is run from a client node, the DAOS agent is fired on that node, and IOR or Field I/O is built if necessary. The IOR wrapper running on the first client node, invokes the IOR benchmark binary with `mpirun`, starting a number of synchronised client processes on all nodes. The Field I/O wrapper (`field_io/test_wrapper.sh`), on all nodes, calls `field_io/test_field_io.sh`, which forks a number of non-synchronised client processes, and each of these processes invokes the field I/O tools described in the `src/field_io` folder.

Access pattern scripts can easily be modified, depending on the study case, to adjust the following:
  - benchmark implementation or mode to employ. Field I/O can be configured to use a single DAOS container for all involved DAOS objects (`--simple-kvs`) or to not index fields (`--simple`)
  - number of client nodes to employ
  - number of client processes per client node to run
  - number of iterations (sequential I/O operations) to be performed by each process
  - DAOS object class
  - I/O and object size
  - number of times to repeat each test
