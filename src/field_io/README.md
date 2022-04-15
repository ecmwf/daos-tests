# DAOS field I/O

Library and tools for writing/reading meteorological fields into/from DAOS.

# Contents

This Cmake project exports a library with a pair of functions to perform writing and reading of weather fields (field I/O) to and from a DAOS cluster, using the DAOS C API. They have been developed based on the design of a domain-specific object store currently employed at ECMWF, the FDB5, so that the type of operations carried out are similar to what is done in operational workflows.

It also exports a corresponding pair of helper binaries to invoke the I/O functions from the command-line given the filename of a weather field in the local file system and/or a field identifier.

# How to install

This project requires the following libraries: daos (with headers), daos-common, gurt and a version of uuid which supports generation of uuids from md5-sums of strings. Such uuid versions are provided in util-linux >= 2.32.

For building, Cmake and ecbuild are required. The Cmake project includes finders to automatically locate required libraries and headers. Usual Cmake parameters can be specified to provide additional hints on where they are located in the file system.

This is an example Cmake call to build the project in a CentOS7 operating system where DAOS and ecbuild have been installed, uuid compiled from source as a static library, and this Cmake project cloned.

```
# install daos in /usr

# compile static uuid from until-linux 2.32 in $HOME/local

# clone ecbuild in $HOME/ecbuild

# clone this cmake project in $HOME/daos-tests/src/field_io

export PATH="$HOME/ecbuild/bin:$PATH"
export DAOS_ROOT="/usr"
export UUID_ROOT="$HOME/local"

build_dir="$HOME/daos-tests-build"
mkdir -p $build_dir
cd $build_dir

ecbuild $HOME/daos-tests/src/field_io \
    -DENABLE_PROFILING="OFF" \
    -DENABLE_SIMPLIFIED="OFF" \
    -DENABLE_SIMPLIFIED_KVS="OFF" \
    -DDAOS_FIELD_IO_OC_MAIN_KV="OC_SX" \
    -DDAOS_FIELD_IO_OC_INDEX_KV="OC_S2" \
    -DDAOS_FIELD_IO_OC_STORE_ARRAY="OC_S1"

cmake --build .
```

Build options are supported to select different variations of the field I/O functions (full / single container / no indexing), whether to enable detailed profiling or not, and the object class for the different DAOS objects involved.

The `docker` folder in this Git repository shows an example of how to install all requirements and build the field I/O project in a CentOS7 operating system.

# Field I/O library

The two functions exposed by the library allow performing a single write or read of a weather field, and have the following signatures.

```
ssize_t daos_write(daos_handle_t poh, daos_handle_t coh,
                   char* index_key, char* store_key,
                   char* data, size_t len, size_t offset,
                   struct timeval * tv_aopen, struct timeval * tv_aclose);

ssize_t daos_read(daos_handle_t poh, daos_handle_t coh,
                  char* index_key, char* store_key,
                  char** rbuf, size_t* len, size_t offset,
                  struct timeval * tv_aopen, struct timeval * tv_aclose);
```

Given an open DAOS pool and container, a main index key, a forecast index key, and a data buffer, they perform storage and indexing of the weather field from/to the data buffer.

# Field I/O tools

The helper binaries allow to perform multiple sequential field I/Os in a process, with several adjustments, and can be invoked as follows.

```
daos_write <POOL_ID> <CONT_ID> <INDEX_DICT> <STORE_DICT> <DATA_PATH> \
           <SIZE_FACTOR> <N_REP> <UNIQUE> <N_TO_WRITE> <HOLD> <SLEEP> \
           <NODE_ID> <CLIENT_ID>

daos_read <POOL_ID> <CONT_ID> <INDEX_DICT> <STORE_DICT> <DATA_PATH> \
          <N_REP> <UNIQUE> <N_TO_READ> <HOLD> <SLEEP> \
          <NODE_ID> <CLIENT_ID> <ALL_TO_FILES>
```

`<POOL_ID>` and `<CONT_ID>` are the UUIDs of an existing DAOS pool and container, respectively, where to store and index the weather field(s).

`<INDEX_DICT>` and `<STORE_DICT>` are JSON dictionaries with the key-value pairs with the most and least-significant part of the identifier of the weather field to store, respectively, with no blank spaces.

`<DATA_PATH>` is the name of a file in the local file system containing the field data to be written (for daos_write) or where to store the read data (for daos_read).

`<SIZE_FACTOR>` is the amount of MiB of data to read from the file and use for the I/O. If the amount specified is larger than the file at `<DATA_PATH>`, the file is read multiple times until enough data is obtained for the desired I/O size.

`<N_REP>` is the number of I/O iterations to perform. The same field data is used for all field I/Os.

`<UNIQUE>` is a flag (0 or 1) which, if disabled, results in use of the same `<INDEX_DICT>` and `<STORE_DICT>` as provided for all `<N_REP>` field I/Os, resulting in repeated updates or reads of the same forecast index entry. If enabled, a unique identifier is appended to `<STORE_DICT>` so that each sequential I/O is performed on a separate forecast index entry.

`<N_TO_WRITE>`/`<N_TO_READ>` is the number of different fields to write or read, respectively, if `<UNIQUE>` is enabled. For example, if `<N_REP>` is set to 10, `<UNIQUE>` is enabled, and `<N_TO_WRITE>` is set to 5, a total of 5 unique `<STORE_DICT>` identifiers will be generated, and 2 field I/O operations will be carried out using each unique identifier.

`<HOLD>` configures the number of seconds to wait before starting the sequential I/Os.

`<SLEEP>` configures the number of seconds to sleep between consecutive I/Os.

The daos_write and daos_read tools can be invoked simultaneously from multiple process in a node or from multiple client nodes. `<NODE_ID>` and `<CLIENT_ID>` must be populated with unique identifiers for the client node and process (respectively) the tools are invoked from, and these identifiers are automatically appended to `<STORE_DICT>` to ensure each parallel client process updates or reads a different entry in the forecast index.

`<ALL_TO_FILES>` is a flag (0 or 1) for daos_read which, if enabled and `<UNIQUE>` is enabled too, each field read in each consecutive iteration is stored in a separate file in the local file system, using `<DATA_PATH>` as pattern and `<NODE_ID>`, `<CLIENT_ID>`, iteration number and `<N_TO_READ>` to generate unique file names.
