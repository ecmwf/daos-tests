/* Copyright 2022 European Centre for Medium-Range Weather Forecasts (ECMWF)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * In applying this licence, ECMWF does not waive the privileges and immunities
 * granted to it by virtue of its status as an intergovernmental organisation nor
 * does it submit to any jurisdiction.
 */

#ifndef daos_field_io_H
#define daos_field_io_H

#include <daos.h>

void cc_init();
void cc_fini();

void oid_alloc_store_init();
void oid_alloc_store_fini();

ssize_t daos_write(daos_handle_t poh, daos_handle_t coh,
				   char* index_key, char* store_key,
				   char* data, size_t len, size_t offset,
				   struct timeval * tv_aopen, struct timeval * tv_aclose);

ssize_t daos_read(daos_handle_t poh, daos_handle_t coh,
				  char* index_key, char* store_key,
				  char** rbuf, size_t* len, size_t offset,
				  struct timeval * tv_aopen, struct timeval * tv_aclose);

#endif
