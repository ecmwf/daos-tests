# DAOS weather field I/O tests

[![DOI](https://zenodo.org/badge/481195353.svg)](https://zenodo.org/badge/latestdoi/481195353)

This repository contains source code implementing simplified weather field I/O to and from DAOS, as well as a collection of scripts to run different field I/O workloads for benchmarking. The scripts can optionally be configured to perform the field I/O operations against a distributed file system, by means of a dummy DAOS library which maps DAOS concepts to file system concepts. Scripts for running the IOR benchmark to generate benchmarking workloads similar to field I/O are also provided.

The repository is intended as complementary material of preliminary DAOS benchmarking results published by ECMWF and EPCC, and no further development or user support is planned. For any questions, see author contact details in the publication.

The `src` folder contains a Cmake project called `field_io`, which provides C libraries and tools to perform one or multiple sequential field I/O operations against DAOS from a single process. The project is documented with more detail in its README.

The `docker` folder contains a Dockerfile which shows how to build the field I/O tools.

The `ngio` folder contains scripts and configuration employed to deploy and run DAOS clusters in the NEXTGenIO platform, and scripts used to run both IOR and the field I/O tools from multiple parallel processes and client nodes in that platform, generating I/O workloads of interest (access patterns) for benchmarking.
