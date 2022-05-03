# Copyright 2022 European Centre for Medium-Range Weather Forecasts (ECMWF)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#	 http://www.apache.org/licenses/LICENSE-2.0
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

FROM registry.hub.docker.com/library/centos:7.9.2009
ARG proxy=

ENV daos_version=v2.0.1
ENV http_proxy=$proxy
ENV https_proxy=$proxy

RUN set -eux \
	&& echo "http_caching=packages" >> /etc/yum.conf \
	&& yum makecache \
	&& yum update -y

# Install basic requirements
RUN set -eux \
	&& yum install -y wget git centos-release-scl \
	&& yum install -y devtoolset-8-gcc-c++ \
	&& yum install -y autoconf automake

# Install ipmctl
RUN set -eux \
	&& wget http://download-ib01.fedoraproject.org/pub/epel/7/x86_64/Packages/e/epel-release-7-14.noarch.rpm \
	&& rpm -Uvh epel-release*rpm \
	&& yum install -y libipmctl cmake3

# Install DAOS
RUN set -eux \
	&& wget -O /etc/yum.repos.d/daos-packages.repo https://packages.daos.io/${daos_version}/CentOS7/packages/x86_64/daos_packages.repo \
	&& wget -O /etc/yum.repos.d/daos-source.repo http://packages.daos.io/${daos_version}/CentOS7/source/daos_source.repo \
	&& rpm --import https://packages.daos.io/RPM-GPG-KEY \
	&& yum install -y epel-release daos-server daos-client daos-devel

# Build libuuid with md5 support
RUN set -eux \
	&& install_dir=$HOME/local \
	&& mkdir -p $install_dir/rpms \
	&& cd $install_dir/rpms \
	&& wget http://vault.centos.org/8.3.2011/BaseOS/Source/SPackages/util-linux-2.32.1-24.el8.src.rpm \
	&& cd $install_dir \
	&& mkdir $install_dir/src \
	&& cd $install_dir/src \
	&& rpm2cpio $install_dir/rpms/util-linux-2.32.1-24.el8.src.rpm | cpio -id \
	&& tar -xf util-linux-2.32.1.tar.xz \
	&& cd $install_dir/src/util-linux-2.32.1 \
	&& export PATH="/opt/rh/devtoolset-8/root/usr/bin:$PATH" \
	&& autoconf \
	&& aclocal \
	&& automake \
	&& ./configure --disable-all-programs --enable-libuuid \
	&& make \
	&& uuid_static_lib=$(find $(pwd) -iname "*libuuid.a*" | tail -n 1) \
	&& uuid_headers=$(find $(pwd) -iname "*uuid.h*" | tail -n 1) \
	&& cd $install_dir \
	&& cp $uuid_static_lib . \
	&& cp $uuid_headers . \
	&& rm -rf rpms src

# Install ecbuild
RUN set -eux \
	&& cd \
	&& git clone https://github.com/ecmwf/ecbuild.git

# Build
COPY src /root/daos-tests/src
RUN set -eux \
	&& export PATH="$HOME/ecbuild/bin:$PATH" \
	&& export DAOS_ROOT="/usr" \
	&& export UUID_ROOT="$HOME/local" \
	&& build_dir="$HOME/daos-tests-build" \
	&& mkdir -p $build_dir \
	&& cd $build_dir \
	&& ecbuild --cmakebin=cmake3 $HOME/daos-tests/src/field_io \
		-DENABLE_PROFILING="OFF" \
		-DENABLE_SIMPLIFIED="OFF" \
		-DENABLE_SIMPLIFIED_KVS="OFF" \
		-DDAOS_FIELD_IO_OC_MAIN_KV="OC_SX" \
		-DDAOS_FIELD_IO_OC_INDEX_KV="OC_S2" \
		-DDAOS_FIELD_IO_OC_STORE_ARRAY="OC_S1" \
		-DCMAKE_C_COMPILER=/opt/rh/devtoolset-8/root/usr/bin/gcc \
		-DCMAKE_CXX_COMPILER=/opt/rh/devtoolset-8/root/usr/bin/g++ \
	&& cmake3 --build .
