# DAOS weather field I/O tests

This repository contains source code implementing simplified weather field I/O to and from DAOS, as well as a collection of scripts to run different field I/O workloads for benchmarking. Scripts for running the IOR benchmark to generate similar benchmarking workloads are also provided. The repository is intended as complementary material of preliminary DAOS benchmarking results published by ECMWF, and no further development or user support is planned. For any questions, see author contact details in the publication.

The `src` folder contains a Cmake project called `field_io`, which provides C libraries and tools to perform one or multiple sequential field I/O operations against DAOS from a single process. The project is documented with more detail in its README.

The `docker` folder contains a Dockerfile which shows how to build the field I/O tools.

The `ngio` folder contains scripts and configuration employed to deploy and run DAOS clusters in the NEXTGenIO platform, and scripts used to run both IOR and the field I/O tools from multiple parallel processes and client nodes in that platform, generating I/O workloads of interest (access patterns) for benchmarking.
