# Building DAOS and Field I/O in Docker

This docker image is intended as an example of the build process of the library and tools provided in the `src/field_io` folder of this Git project, and can also be used for developing or debugging them.

To build the image, clone this Git repository on a machine with Docker available, change directories to the root folder of the Git project and run the following, setting a proxy if necessary:
```
docker build . -f docker/Dockerfile -t daos_field_io [--build-arg proxy=http://your.proxy:your_port]
```
