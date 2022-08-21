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

#include <inttypes.h>

#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>

#include "daos_field_io.h"
#include "daos_field_io_version.h"
#include "daos_field_io_config.h"

#include <uuid/uuid.h>

#define UUIDLEN 16
#ifdef daos_field_io_HAVE_SIMPLIFIED
// objid(16) + struct_timeval(16)
#define REFLEN 32
#else
  #ifdef daos_field_io_HAVE_SIMPLIFIED_KVS
// objid(16) + struct_timeval(16)
#define REFLEN 32
  #else
// cid(16) + objid(16) + struct_timeval(16)
#define REFLEN 48
  #endif
#endif
#define BUFSIZE 10
#define BLKSIZE 1048576
#define OIDS_PER_ALLOC 1024

//void uuid_generate_md5(uuid_t out, const uuid_t ns, const char *name, size_t len);

char * oc_main_kv_str = DAOS_FIELD_IO_OC_MAIN_KV;
char * oc_index_kv_str = DAOS_FIELD_IO_OC_INDEX_KV;
char * oc_store_array_str = DAOS_FIELD_IO_OC_STORE_ARRAY;

daos_oclass_id_t str_to_oc(char * in) {
	daos_oclass_id_t oc = OC_RESERVED;
	if (strcmp(in, "OC_S1") == 0) oc = OC_S1;
	if (strcmp(in, "OC_S2") == 0) oc = OC_S2;
	if (strcmp(in, "OC_SX") == 0) oc = OC_SX;
	return oc;
}

/// Cont handle cache

struct coh_cache {
	daos_handle_t key1;
	uuid_t key2;
	unsigned int key3;
	daos_handle_t value;
	struct coh_cache * next;
};

struct coh_cache * cc;
bool cc_use = 0;

void cc_init() {
	cc = NULL;
	cc_use = 1;
}

void cc_fini() {

	struct coh_cache * cc_visit = cc;
	struct coh_cache * tmp;
	int rc;

	while (cc_visit != NULL) {

		rc = daos_cont_close(cc_visit->value, NULL);

		if (rc != 0) {
			printf("daos_cont_close in cache failed with %d", rc);
		}

		tmp = cc_visit;
		cc_visit = cc_visit->next;
		free(tmp);

	}

	cc = NULL;
	cc_use = 0;

}

int daos_cont_open_cache(daos_handle_t poh, uuid_t co_uuid, unsigned int mode, daos_handle_t * coh) {

	struct coh_cache * cc_visit = cc;
	struct coh_cache * new_entry;
	int rc;
	char co_uuid_str_1[37] = "";
	char co_uuid_str_2[37] = "";

	while (cc_visit != NULL) {

		uuid_t co_uuid_cache;
		memcpy(&(co_uuid_cache[0]), &(cc_visit->key2[0]), sizeof(uuid_t));

		if (memcmp(&(cc_visit->key1), &poh, sizeof(daos_handle_t)) == 0 && 
			memcmp(&(cc_visit->key2[0]), &(co_uuid[0]), sizeof(uuid_t)) == 0 && 
			cc_visit->key3 == mode) {
			*coh = cc_visit->value;
			return 0;
		}

		cc_visit = cc_visit->next;

	}

	rc = daos_cont_open(poh, co_uuid, mode, coh, NULL, NULL);

	if (rc == 0) {

		new_entry = (struct coh_cache *) malloc(sizeof(struct coh_cache));

		new_entry->key1 = poh;
		memcpy(&(new_entry->key2[0]), &(co_uuid[0]), sizeof(uuid_t));
		new_entry->key3 = mode;
		new_entry->value = *coh;
		new_entry->next = NULL;

		if (cc != NULL) {
			new_entry->next = cc;
		}

		cc = new_entry;

	}

	return rc;

}

/// Oid alloc store

struct oid_alloc {
	daos_handle_t coh;
	uint64_t next_oid;
	int num_oids;
	struct oid_alloc * next;
};

struct oid_alloc * oid_alloc_store;

void oid_alloc_store_init() {
	oid_alloc_store = NULL;
}

void oid_alloc_store_fini() {

	struct oid_alloc * oid_alloc_visit = oid_alloc_store;
	struct oid_alloc * tmp;
	int rc;

	while (oid_alloc_visit != NULL) {

		tmp = oid_alloc_visit;
		oid_alloc_visit = oid_alloc_visit->next;
		free(tmp);

	}

	oid_alloc_store = NULL;

}

static int get_oid(daos_handle_t coh, daos_obj_id_t* oid) {

	struct oid_alloc * oid_alloc_visit = oid_alloc_store;
	struct oid_alloc * new_entry;
	int rc, num_oids;

	while (oid_alloc_visit != NULL) {

		if (memcmp(&(oid_alloc_visit->coh), &coh, sizeof(daos_handle_t)) == 0) {
			break;
		}

		oid_alloc_visit = oid_alloc_visit->next;

	}

	if (oid_alloc_visit == NULL) {

		new_entry = (struct oid_alloc *) malloc(sizeof(struct oid_alloc));

		new_entry->coh = coh;
		new_entry->num_oids = 0;
		new_entry->next = oid_alloc_store;

		oid_alloc_store = new_entry;
		oid_alloc_visit = oid_alloc_store;

	}

	if (oid_alloc_visit->num_oids == 0) {

		num_oids = OIDS_PER_ALLOC;
		rc = daos_cont_alloc_oids(coh, num_oids + 1, &(oid_alloc_visit->next_oid), NULL);
		if (rc != 0) {
				return rc;
		}
		oid_alloc_visit->num_oids = num_oids;

	}

	oid->lo = oid_alloc_visit->next_oid;
	oid_alloc_visit->next_oid += 1;
	oid_alloc_visit->num_oids -= 1;

	return 0;

}

#ifdef daos_field_io_HAVE_PROFILING
static bool prof = 1;
#else
static bool prof = 0;
#endif

static void p_s(struct timeval *before) {

	if (prof) gettimeofday(before, NULL);

}

static void p_e(const char * wr, const char * f, 
	 struct timeval *before, struct timeval *after, struct timeval *result) {

	char tabs[BUFSIZE] = "\t\t";
	if (prof) {
		if (strlen(f) > 16) tabs[1] = '\0';
		gettimeofday(after, NULL);
		timersub(after, before, result);
		printf("Profiling daos_field_io daos_%s - %s: %s%ld.%06ld\n", wr, f, tabs,
			(long int)result->tv_sec, (long int)result->tv_usec);
	}

}

ssize_t daos_write(daos_handle_t poh, daos_handle_t coh, 
		   char* index_key, char* store_key, 
		   char* data, size_t len, size_t offset,
		   struct timeval * tv_aopen, struct timeval * tv_aclose) {

#ifdef daos_field_io_HAVE_SIMPLIFIED

	daos_obj_id_t oid_array, oid_kv;
	daos_handle_t oh_array, oh_kv;
	daos_size_t size;

	uuid_t array_uuid, seed, index_key_uuid;

	int rc;
	ssize_t res = (ssize_t) -1;

	// profiling
	struct timeval tval_before, tval_after, tval_result;

	daos_oclass_id_t oc_main_kv = str_to_oc(oc_main_kv_str);
	daos_oclass_id_t oc_index_kv = str_to_oc(oc_index_kv_str);
	daos_oclass_id_t oc_store_array = str_to_oc(oc_store_array_str);

	/* 
	 * build id for array object
	 */

	oid_array.hi = 0;
	oid_array.lo = 0;

	// the uuid of the index kv is determined as the md5 of the index key
	p_s(&tval_before);
	rc = uuid_parse("00000000-0000-0000-0000-000000000000", seed);
	p_e("write", "uuid_parse", &tval_before, &tval_after, &tval_result);
	p_s(&tval_before);
	uuid_generate_md5(index_key_uuid, seed, index_key, strlen(index_key));
	p_e("write", "uuid_generate_md5", &tval_before, &tval_after, &tval_result);
	p_s(&tval_before);
	uuid_generate_md5(array_uuid, index_key_uuid, store_key, strlen(store_key));
	p_e("write", "uuid_generate_md5_2", &tval_before, &tval_after, &tval_result);

	memcpy(&(oid_array.hi), &(array_uuid[0]), sizeof(uint64_t));
	memcpy(&(oid_array.lo), &(array_uuid[0]) + sizeof(uint64_t), sizeof(uint64_t));

	/*
	 * create and open array object
	 */

	p_s(&tval_before);
	daos_array_generate_oid(coh, &oid_array, true, oc_store_array, 0, 0);
	p_e("write", "daos_array_generate_oid", &tval_before, &tval_after, &tval_result);
	gettimeofday(tv_aopen, NULL);
	p_s(&tval_before);
	rc = daos_array_create(coh, oid_array, DAOS_TX_NONE, 1, BLKSIZE, &oh_array, NULL);
	p_e("write", "daos_array_create", &tval_before, &tval_after, &tval_result);

	if (rc == -1004) {
		daos_size_t cell_size, csize;
		p_s(&tval_before);
		rc = daos_array_open(coh, oid_array, DAOS_TX_NONE, DAOS_OO_RW, 
				 &cell_size, &csize, &oh_array, NULL);
		p_e("write", "daos_array_open", &tval_before, &tval_after, &tval_result);
		if (rc != 0) {
		printf("array open failed with %d", rc);
		}
	} else if (rc != 0) {
		printf("array create failed with %d", rc);
		goto exit;
	}

	/* 
	 * write data
	 */

	bool failed = 0;

	daos_array_iod_t iod;
	d_sg_list_t sgl;
	daos_range_t rg;
	d_iov_t iov;

	iod.arr_nr = 1;
	rg.rg_len = len;
	rg.rg_idx = offset;
	iod.arr_rgs = &rg;

	sgl.sg_nr = 1;
	d_iov_set(&iov, data, len);
	sgl.sg_iovs = &iov;

	p_s(&tval_before);
	rc = daos_array_write(oh_array, DAOS_TX_NONE, &iod, &sgl, NULL);
	p_e("write", "daos_array_write", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("array write failed with %d", rc);
		failed = 1;
		// closing it just after
	}

	p_s(&tval_before);
	rc = daos_array_close(oh_array, NULL);
	p_e("write", "daos_array_close", &tval_before, &tval_after, &tval_result);

	gettimeofday(tv_aclose, NULL);

	if (rc != 0) {
		printf("array close failed with %d", rc);
		failed = 1;
	}

	if (failed) {
		goto exit;
	}

	res = len;

exit:
	return res;

#else

  #ifdef daos_field_io_HAVE_SIMPLIFIED_KVS

	daos_obj_id_t oid_array, oid_kv, oid_kv_index;
	daos_handle_t oh_array, oh_kv, oh_kv_index;
	daos_size_t size;

	uuid_t index_kv_uuid, seed;

	int rc;
	ssize_t res = (ssize_t) -1;

	char index_oid_buf[2 * sizeof(uint64_t)];

	// profiling
	struct timeval tval_before, tval_after, tval_result;

	daos_oclass_id_t oc_main_kv = str_to_oc(oc_main_kv_str);
	daos_oclass_id_t oc_index_kv = str_to_oc(oc_index_kv_str);
	daos_oclass_id_t oc_store_array = str_to_oc(oc_store_array_str);

	/* 
	 * build id for main kv object
	 */

	oid_kv.hi = 0;
	oid_kv.lo = 0;
	p_s(&tval_before);
	daos_obj_generate_oid(coh, &oid_kv, DAOS_OT_KV_HASHED, oc_main_kv, 0, 0);
	p_e("write", "daos_obj_generate_oid", &tval_before, &tval_after, &tval_result);

	/* 
	 * open/create the main kv in the provided container
	 */

	p_s(&tval_before);
	rc = daos_kv_open(coh, oid_kv, DAOS_OO_RW, &oh_kv, NULL);
	p_e("write", "daos_kv_open", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("main kv open failed with %d", rc);
		goto exit;
	}

	/*
	 * check presence of index_key in the main kv
	 */

	// the uuid of the index kv is determined as the md5 of the index key
	p_s(&tval_before);
	rc = uuid_parse("00000000-0000-0000-0000-000000000000", seed);
	p_e("write", "uuid_parse", &tval_before, &tval_after, &tval_result);
	p_s(&tval_before);
	uuid_generate_md5(index_kv_uuid, seed, index_key, strlen(index_key));
	p_e("write", "uuid_generate_md5", &tval_before, &tval_after, &tval_result);

	p_s(&tval_before);
	rc = daos_kv_get(oh_kv, DAOS_TX_NONE, 0, index_key, &size, NULL, NULL);
	p_e("write", "daos_kv_get", &tval_before, &tval_after, &tval_result);

	if (rc == 0 && size == 0) {

		memcpy(&(oid_kv_index.hi), &(index_kv_uuid[0]), sizeof(uint64_t));
		memcpy(&(oid_kv_index.lo), &(index_kv_uuid[0]) + sizeof(uint64_t), sizeof(uint64_t));

		p_s(&tval_before);
		daos_obj_generate_oid(coh, &oid_kv_index, DAOS_OT_KV_HASHED, oc_index_kv, 0, 0);
		p_e("write", "daos_obj_generate_oid", &tval_before, &tval_after, &tval_result);

		/* 
		 * registering the index kv oid in the main kv
		 *
		 * if, after a race condition in daos_kv_get, multiple processes call 
		 * daos_cont_create for the same container uuid, all of them will
		 * get a rc = 0, and will execute the following daos_kv_put
		 */

		memcpy(index_oid_buf, &(oid_kv_index.hi), sizeof(uint64_t));
		memcpy(index_oid_buf + sizeof(uint64_t), &(oid_kv_index.lo), sizeof(uint64_t));

		p_s(&tval_before);
		rc = daos_kv_put(oh_kv, DAOS_TX_NONE, 0, index_key, 2 * sizeof(uint64_t), index_oid_buf, NULL);
		p_e("write", "daos_kv_put", &tval_before, &tval_after, &tval_result);

		if (rc != 0) {
			printf("main kv put failed");
			goto close_kv;
		}

	} else if (rc == 0) {

		/*
		 * read in the oid of the index kv
		 */

		p_s(&tval_before);
		rc = daos_kv_get(oh_kv, DAOS_TX_NONE, 0, index_key, &size, index_oid_buf, NULL);
		p_e("write", "daos_kv_get_2", &tval_before, &tval_after, &tval_result);

		if (rc != 0) {
			printf("main kv get failed with %d", rc);
			goto close_kv;
		}

		memcpy(&(oid_kv_index.hi), index_oid_buf, sizeof(uint64_t));
		memcpy(&(oid_kv_index.lo), index_oid_buf + sizeof(uint64_t), sizeof(uint64_t));

	} else if (rc != 0) {

		printf("main kv size get failed with %d", rc);
		goto close_kv;

	}

	/* 
	 * open/create the index kv
	 */

	p_s(&tval_before);
	rc = daos_kv_open(coh, oid_kv_index, DAOS_OO_RW, &oh_kv_index, NULL);
	p_e("write", "daos_kv_open_2", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("index kv open failed with %d", rc);
		goto close_kv;
	}

	/*
	 * create and open array object
	 */

	struct timeval tval_before_aopen, tval_after_aclose, tval_result_aopenclose;

	p_s(&tval_before);
	rc = get_oid(coh, &oid_array);
	p_e("write", "get_oid_2", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("get_oid_2 failed with %d", rc);
		goto close_index_kv;
	}

	p_s(&tval_before);
	daos_array_generate_oid(coh, &oid_array, true, oc_store_array, 0, 0);
	p_e("write", "daos_array_generate_oid", &tval_before, &tval_after, &tval_result);

	gettimeofday(tv_aopen, NULL);
	p_s(&tval_before);
	rc = daos_array_create(coh, oid_array, DAOS_TX_NONE, 1, BLKSIZE, &oh_array, NULL);
	p_e("write", "daos_array_create", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("array create failed with %d", rc);
		goto close_index_kv;
	}

	/* 
	 * write data
	 */

	bool failed = 0;

	daos_array_iod_t iod;
	d_sg_list_t sgl;
	daos_range_t rg;
	d_iov_t iov;

	iod.arr_nr = 1;
	rg.rg_len = len;
	rg.rg_idx = offset;
	iod.arr_rgs = &rg;

	sgl.sg_nr = 1;
	d_iov_set(&iov, data, len);
	sgl.sg_iovs = &iov;

	p_s(&tval_before);
	rc = daos_array_write(oh_array, DAOS_TX_NONE, &iod, &sgl, NULL);
	p_e("write", "daos_array_write", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("array write failed with %d", rc);
		failed = 1;
		// closing it just after
	}

	p_s(&tval_before);
	rc = daos_array_close(oh_array, NULL);
	p_e("write", "daos_array_close", &tval_before, &tval_after, &tval_result);

	gettimeofday(tv_aclose, NULL);

	if (rc != 0) {
		printf("array close failed with %d", rc);
		failed = 1;
	}

	if (failed) {
		goto close_index_kv;
	}

	/* 
	 * write store_key:array_obj_id,timestamp into index kv
	 */

	char ref_buf[REFLEN] = "";

	struct timeval timestamp;

	gettimeofday(&timestamp, NULL);

	memcpy(ref_buf, &(oid_array.hi), sizeof(uint64_t));
	memcpy(ref_buf + sizeof(uint64_t), &(oid_array.lo), sizeof(uint64_t));
	memcpy(ref_buf + 2 * sizeof(uint64_t), &(timestamp), sizeof(struct timeval));

	p_s(&tval_before);
	rc = daos_kv_put(oh_kv_index, DAOS_TX_NONE, 0, store_key, REFLEN, ref_buf, NULL);
	p_e("write", "daos_kv_put_3", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("index kv put failed");
		goto close_index_kv;
	}

	res = len;

close_index_kv:
	p_s(&tval_before);
	rc = daos_obj_close(oh_kv_index, NULL);
	p_e("write", "daos_obj_close_1", &tval_before, &tval_after, &tval_result);
close_kv:
	p_s(&tval_before);
	rc = daos_obj_close(oh_kv, NULL);
	p_e("write", "daos_obj_close_2", &tval_before, &tval_after, &tval_result);
exit:
	return res;

  #else

	daos_obj_id_t oid_array, oid_kv, oid_kv_index;
	daos_handle_t oh_array, oh_kv, oh_kv_index;
	daos_size_t size;

	uuid_t index_co_uuid, store_co_uuid, seed;
	daos_handle_t index_coh, store_coh;

	char co_uuid_buf[1 * UUIDLEN];  // = "";
	char store_co_uuid_buf[1 * UUIDLEN] = "";

	int rc;
	ssize_t res = (ssize_t) -1;

	char index_co_uuid_str[37];
	char store_co_uuid_str[37];

	// profiling
	struct timeval tval_before, tval_after, tval_result;

	daos_oclass_id_t oc_main_kv = str_to_oc(oc_main_kv_str);
	daos_oclass_id_t oc_index_kv = str_to_oc(oc_index_kv_str);
	daos_oclass_id_t oc_store_array = str_to_oc(oc_store_array_str);

	/* 
	 * build id for main kv object
	 */

	oid_kv.hi = 0;
	oid_kv.lo = 0;
	p_s(&tval_before);
	daos_obj_generate_oid(coh, &oid_kv, DAOS_OT_KV_HASHED, oc_main_kv, 0, 0);
	p_e("write", "daos_obj_generate_oid", &tval_before, &tval_after, &tval_result);

	/* 
	 * open/create the main kv in the provided container
	 */

	p_s(&tval_before);
	rc = daos_kv_open(coh, oid_kv, DAOS_OO_RW, &oh_kv, NULL);
	p_e("write", "daos_kv_open", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("main kv open failed with %d", rc);
		goto exit;
	}

	/*
	 * check presence of index_key in the main kv
	 *
	 *  Possible race condition if new containers are generated with random uuids:
	 *  two processes may come in and find there are no index and store containers 
	 *  existing for the queried index_key, they will each create a pair of new 
	 *  containers, and then write the index uuids in the kv whenever they finish
	 *  creating the containers. Only the uuids written by the last process will remain
	 *  in the kv, resulting in all the leading processes writing data in isolated 
	 *  containers that won't be referenced anymore anywhere, resulting in data loss.
	 *
	 *  Solution: have a hashing function which deterministically maps a index_key onto 
	 *  valid index and store container uuids. Racing processes will try to create
	 *  containers with the same pair of uuids, but only the first one will effectively
	 *  create them.
	 */

	// the uuid of the index container is determined as the md5 of the index key
	p_s(&tval_before);
	rc = uuid_parse("00000000-0000-0000-0000-000000000000", seed);
	p_e("write", "uuid_parse", &tval_before, &tval_after, &tval_result);
	p_s(&tval_before);
	uuid_generate_md5(index_co_uuid, seed, index_key, strlen(index_key));
	p_e("write", "uuid_generate_md5", &tval_before, &tval_after, &tval_result);

	// the uuid of the store container is determined as the md5 of the index key
	// using the uuid of the index container as seed.
	p_s(&tval_before);
	uuid_generate_md5(store_co_uuid, index_co_uuid, index_key, strlen(index_key));
	p_e("write", "uuid_generate_md5_2", &tval_before, &tval_after, &tval_result);

	p_s(&tval_before);
	rc = daos_kv_get(oh_kv, DAOS_TX_NONE, 0, index_key, &size, NULL, NULL);
	p_e("write", "daos_kv_get", &tval_before, &tval_after, &tval_result);

	if (rc == 0 && size == 0) {

		/*
		 * create index container
		 */

		p_s(&tval_before);
		rc = daos_cont_create(poh, index_co_uuid, NULL, NULL);
		p_e("write", "daos_cont_create", &tval_before, &tval_after, &tval_result);

		if (rc != 0) {
			printf("index container create failed with %d", rc);
			goto close_kv;
		}

		/* 
		 * registering the index container uuid in the main kv
		 *
		 * the timestamp of last time the index was modified won't be kept
		 * because it would have an overhead to maintain it, as the main kv
		 * would have to be modified and updated after the actual data write
		 *
		 * if, after a race condition in daos_kv_get, multiple processes call 
		 * daos_cont_create for the same container uuid, all of them will
		 * get a rc = 0, and will execute the following daos_kv_put
		 */

		memcpy(co_uuid_buf, &(index_co_uuid[0]), UUIDLEN);

		p_s(&tval_before);
		rc = daos_kv_put(oh_kv, DAOS_TX_NONE, 0, index_key, 1 * UUIDLEN, co_uuid_buf, NULL);
		p_e("write", "daos_kv_put", &tval_before, &tval_after, &tval_result);

		if (rc != 0) {
			printf("main kv put failed");
			goto close_kv;
		}

	} else if (rc == 0) {

		/*
		 * read in the uuid of the index container
		 */

		p_s(&tval_before);
		rc = daos_kv_get(oh_kv, DAOS_TX_NONE, 0, index_key, &size, co_uuid_buf, NULL);
		p_e("write", "daos_kv_get_2", &tval_before, &tval_after, &tval_result);

		if (rc != 0) {
			printf("main kv get failed with %d", rc);
			goto close_kv;
		}

		memcpy(&(index_co_uuid[0]), co_uuid_buf, UUIDLEN);

	} else if (rc != 0) {

		printf("main kv size get failed with %d", rc);
		goto close_kv;

	}

	/*
	 * open index container
	 */

	p_s(&tval_before);
	if (cc_use) {
		rc = daos_cont_open_cache(poh, index_co_uuid, DAOS_COO_RW, &index_coh);
	} else {
		rc = daos_cont_open(poh, index_co_uuid, DAOS_COO_RW, &index_coh, NULL, NULL);
	}
	p_e("write", "daos_cont_open", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("index container open failed with %d", rc);
		goto close_kv;
	}

	/* 
	 * build id for index kv object
	 */

	oid_kv_index.hi = 0;
	oid_kv_index.lo = 0;
	p_s(&tval_before);
	daos_obj_generate_oid(index_coh, &oid_kv_index, DAOS_OT_KV_HASHED, oc_index_kv, 0, 0);
	p_e("write", "daos_obj_generate_oid_2", &tval_before, &tval_after, &tval_result);

	/* 
	 * open/create the index kv in the index container
	 */

	p_s(&tval_before);
	rc = daos_kv_open(index_coh, oid_kv_index, DAOS_OO_RW, &oh_kv_index, NULL);
	p_e("write", "daos_kv_open_2", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("index kv open failed with %d", rc);
		goto close_index_cont;
	}

	/*
	 * read in the store_co_uuid key, if exists
	 */

	p_s(&tval_before);
	rc = daos_kv_get(oh_kv_index, DAOS_TX_NONE, 0, "store_co_uuid", &size, NULL, NULL);
	p_e("write", "daos_kv_get_3", &tval_before, &tval_after, &tval_result);

	if (rc == 0 && size == 0) {

		/*
		 * create store container
		 */

		p_s(&tval_before);
		rc = daos_cont_create(poh, store_co_uuid, NULL, NULL);
		p_e("write", "daos_cont_create_2", &tval_before, &tval_after, &tval_result);

		if (rc != 0) {
			printf("store container create failed with %d", rc);
			goto close_index_kv;
		}

		/* 
		 * registering the store container uuid in the index kv
		 *
		 * if, after a race condition in daos_kv_get, multiple processes call 
		 * daos_cont_create for the same container uuid, all of them will
		 * get a rc = 0, and will execute the following daos_kv_put
		 */

		memcpy(store_co_uuid_buf, &(store_co_uuid[0]), UUIDLEN);

		p_s(&tval_before);
		rc = daos_kv_put(oh_kv_index, DAOS_TX_NONE, 0, "store_co_uuid", 
				 1 * UUIDLEN, store_co_uuid_buf, NULL);
		p_e("write", "daos_kv_put_2", &tval_before, &tval_after, &tval_result);

		if (rc != 0) {
			printf("index kv put of store_co_uuid failed");
			goto close_index_kv;
		}

	} else if (rc == 0) {

		/*
		 * read in the uuid of the store container
		 */

		p_s(&tval_before);
		rc = daos_kv_get(oh_kv_index, DAOS_TX_NONE, 0, "store_co_uuid", 
				 &size, store_co_uuid_buf, NULL);
		p_e("write", "daos_kv_get_4", &tval_before, &tval_after, &tval_result);

		if (rc != 0) {
			printf("index kv get of store_co_uuid failed with %d", rc);
			goto close_index_kv;
		}

		memcpy(&(store_co_uuid[0]), store_co_uuid_buf, UUIDLEN);

	} else if (rc != 0) {

		printf("index kv size get of store_co_uuid failed with %d", rc);
		goto close_index_kv;

	}

	/*
	 *  open store container
	 */

	p_s(&tval_before);
	if (cc_use) {
		rc = daos_cont_open_cache(poh, store_co_uuid, DAOS_COO_RW, &store_coh);
	} else {
		rc = daos_cont_open(poh, store_co_uuid, DAOS_COO_RW, &store_coh, NULL, NULL);
	}
	p_e("write", "daos_cont_open_2", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("store container open failed with %d", rc);
		goto close_index_kv;
	}

	/*
	 * create and open array object
	 */

	struct timeval tval_before_aopen, tval_after_aclose, tval_result_aopenclose;

	uuid_unparse(store_co_uuid, store_co_uuid_str);	
	p_s(&tval_before);
	rc = get_oid(store_coh, &oid_array);
	p_e("write", "get_oid", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("get_oid failed with %d", rc);
		goto close_store_cont;
	}

	p_s(&tval_before);
	daos_array_generate_oid(store_coh, &oid_array, true, oc_store_array, 0, 0);
	p_e("write", "daos_array_generate_oid", &tval_before, &tval_after, &tval_result);
	gettimeofday(tv_aopen, NULL);
	p_s(&tval_before);
	rc = daos_array_create(store_coh, oid_array, DAOS_TX_NONE, 1, BLKSIZE, &oh_array, NULL);
	p_e("write", "daos_array_create", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("array create failed with %d", rc);
		goto close_store_cont;
	}

	/* 
	 * write data
	 */

	bool failed = 0;

	daos_array_iod_t iod;
	d_sg_list_t sgl;
	daos_range_t rg;
	d_iov_t iov;

	iod.arr_nr = 1;
	rg.rg_len = len;
	rg.rg_idx = offset;
	iod.arr_rgs = &rg;

	sgl.sg_nr = 1;
	d_iov_set(&iov, data, len);
	sgl.sg_iovs = &iov;

	p_s(&tval_before);
	rc = daos_array_write(oh_array, DAOS_TX_NONE, &iod, &sgl, NULL);
	p_e("write", "daos_array_write", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("array write failed with %d", rc);
		failed = 1;
		// closing it just after
	}

	p_s(&tval_before);
	rc = daos_array_close(oh_array, NULL);
	p_e("write", "daos_array_close", &tval_before, &tval_after, &tval_result);

	gettimeofday(tv_aclose, NULL);

	if (rc != 0) {
		printf("array close failed with %d", rc);
		failed = 1;
	}

	if (failed) {
		goto close_store_cont;
	}

	char ref_buf[REFLEN] = "";

	/* 
	 * write store_key:store_co_uuid,array_obj_id,timestamp into index kv
	 */

	struct timeval timestamp;

	gettimeofday(&timestamp, NULL);

	memcpy(ref_buf, &(store_co_uuid[0]), UUIDLEN);
	memcpy(ref_buf + UUIDLEN, &(oid_array.hi), sizeof(uint64_t));
	memcpy(ref_buf + UUIDLEN + sizeof(uint64_t), &(oid_array.lo), sizeof(uint64_t));
	memcpy(ref_buf + UUIDLEN + 2 * sizeof(uint64_t), &(timestamp), sizeof(struct timeval));

	p_s(&tval_before);
	rc = daos_kv_put(oh_kv_index, DAOS_TX_NONE, 0, store_key, REFLEN, ref_buf, NULL);
	p_e("write", "daos_kv_put_3", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("index kv put failed");
		goto close_store_cont;
	}

	res = len;

close_store_cont:
	if (!cc_use) {
		p_s(&tval_before);
		rc = daos_cont_close(store_coh, NULL);
		p_e("write", "daos_cont_close_1", &tval_before, &tval_after, &tval_result);
	}
close_index_kv:
	p_s(&tval_before);
	rc = daos_obj_close(oh_kv_index, NULL);
	p_e("write", "daos_obj_close_1", &tval_before, &tval_after, &tval_result);
close_index_cont:
	if (!cc_use) {
		p_s(&tval_before);
		rc = daos_cont_close(index_coh, NULL);
		p_e("write", "daos_cont_close_2", &tval_before, &tval_after, &tval_result);
	}
close_kv:
	p_s(&tval_before);
	rc = daos_obj_close(oh_kv, NULL);
	p_e("write", "daos_obj_close_2", &tval_before, &tval_after, &tval_result);
exit:
	return res;

  #endif

#endif

}



ssize_t daos_read(daos_handle_t poh, daos_handle_t coh, 
		  char* index_key, char* store_key,
		  char** rbuf, size_t* len, size_t offset,
		  struct timeval * tv_aopen, struct timeval * tv_aclose) {

#ifdef daos_field_io_HAVE_SIMPLIFIED

	daos_obj_id_t oid_array, oid_kv;
	daos_handle_t oh_array, oh_kv;
	daos_size_t size;

	uuid_t array_uuid, seed, index_key_uuid;

	int rc;
	ssize_t res = (ssize_t) -1;

	// profiling
	struct timeval tval_before, tval_after, tval_result;

	daos_oclass_id_t oc_main_kv = str_to_oc(oc_main_kv_str);
	daos_oclass_id_t oc_index_kv = str_to_oc(oc_index_kv_str);
	daos_oclass_id_t oc_store_array = str_to_oc(oc_store_array_str);

	/* 
	 * build id for array object
	 */

	oid_array.hi = 0;
	oid_array.lo = 0;

	// the uuid of the index kv is determined as the md5 of the index key
	p_s(&tval_before);
	rc = uuid_parse("00000000-0000-0000-0000-000000000000", seed);
	p_e("read", "uuid_parse", &tval_before, &tval_after, &tval_result);
	p_s(&tval_before);
	uuid_generate_md5(index_key_uuid, seed, index_key, strlen(index_key));
	p_e("read", "uuid_generate_md5", &tval_before, &tval_after, &tval_result);
	p_s(&tval_before);
	uuid_generate_md5(array_uuid, index_key_uuid, store_key, strlen(store_key));
	p_e("read", "uuid_generate_md5_2", &tval_before, &tval_after, &tval_result);

	memcpy(&(oid_array.hi), &(array_uuid[0]), sizeof(uint64_t));
	memcpy(&(oid_array.lo), &(array_uuid[0]) + sizeof(uint64_t), sizeof(uint64_t));

	p_s(&tval_before);
	daos_array_generate_oid(coh, &oid_array, true, oc_store_array, 0, 0);
	p_e("read", "daos_array_generate_oid", &tval_before, &tval_after, &tval_result);

	/*
	 * open array object
	 */

	daos_size_t cell_size, csize;

	gettimeofday(tv_aopen, NULL);
	p_s(&tval_before);
	rc = daos_array_open(coh, oid_array, DAOS_TX_NONE, DAOS_OO_RW,
				 &cell_size, &csize, &oh_array, NULL);
	p_e("read", "daos_array_open", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("array open failed with %d", rc);
		goto exit;
	}

	/*
	 * read array size and allocate buffer
	 */

	daos_size_t array_size;
	p_s(&tval_before);
	rc = daos_array_get_size(oh_array, DAOS_TX_NONE, &array_size, NULL);
	p_e("read", "daos_array_get_size", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("array get size failed with %d", rc);
		goto close_array;
	}

	char *out = NULL;
	p_s(&tval_before);
	out = (char*) realloc(out, array_size * sizeof(char));
	p_e("read", "realloc", &tval_before, &tval_after, &tval_result);

	/*
	 * read array
	 */

	daos_array_iod_t iod;
	d_sg_list_t sgl;
	daos_range_t rg;
	d_iov_t iov;

	iod.arr_nr = 1;
	rg.rg_len = array_size;
	rg.rg_idx = offset;
	iod.arr_rgs = &rg;

	sgl.sg_nr = 1;
	d_iov_set(&iov, out, array_size);
	sgl.sg_iovs = &iov;

	p_s(&tval_before);
	rc = daos_array_read(oh_array, DAOS_TX_NONE, &iod, &sgl, NULL);
	p_e("read", "daos_array_read", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("array read failed with %d", rc);
		goto close_array;
	}

	*rbuf = out;

	*len = (ssize_t) array_size;
	res = (ssize_t) array_size;

close_array:
	p_s(&tval_before);
	rc = daos_array_close(oh_array, NULL);
	p_e("read", "daos_array_close", &tval_before, &tval_after, &tval_result);

	gettimeofday(tv_aclose, NULL);
exit:
	return res;

#else

  #ifdef daos_field_io_HAVE_SIMPLIFIED_KVS

	daos_obj_id_t oid_array, oid_kv, oid_kv_index;
	daos_handle_t oh_array, oh_kv, oh_kv_index;
	daos_size_t size;

	char index_oid_buf[2 * sizeof(uint64_t)] = "";

	int rc;
	ssize_t res = (ssize_t) -1;

	// profiling
	struct timeval tval_before, tval_after, tval_result;

	daos_oclass_id_t oc_main_kv = str_to_oc(oc_main_kv_str);
	daos_oclass_id_t oc_index_kv = str_to_oc(oc_index_kv_str);
	daos_oclass_id_t oc_store_array = str_to_oc(oc_store_array_str);

	/* 
	 * build id for main kv object
	 */

	oid_kv.hi = 0;
	oid_kv.lo = 0;
	p_s(&tval_before);
	daos_obj_generate_oid(coh, &oid_kv, DAOS_OT_KV_HASHED, oc_main_kv, 0, 0);
	p_e("read", "daos_obj_generate_oid", &tval_before, &tval_after, &tval_result);

	/*
	 * open/create the main kv in the provided container
	 */

	p_s(&tval_before);
	rc = daos_kv_open(coh, oid_kv, DAOS_OO_RW, &oh_kv, NULL);
	p_e("read", "daos_kv_open", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("main kv open failed with %d", rc);
		goto exit;
	}

	/*
	 * check presence of index_key in the main kv
	 */

	p_s(&tval_before);
	rc = daos_kv_get(oh_kv, DAOS_TX_NONE, 0, index_key, &size, NULL, NULL);
	p_e("read", "daos_kv_get", &tval_before, &tval_after, &tval_result);

	if (rc == 0 && size == 0) {

		/*
		 * print error and return
		 */
		printf("not found");
		goto close_kv;

	} else if (rc != 0) {

		printf("main kv size get failed with %d", rc);
		goto close_kv;

	}

	p_s(&tval_before);
	rc = daos_kv_get(oh_kv, DAOS_TX_NONE, 0, index_key, &size, index_oid_buf, NULL);
	p_e("read", "daos_kv_get_2", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("main kv get failed with %d", rc);
		goto close_kv;
	}

	oid_kv_index.hi = 0;
	oid_kv_index.lo = 0;

	memcpy(&(oid_kv_index.hi), index_oid_buf, sizeof(uint64_t));
	memcpy(&(oid_kv_index.lo), index_oid_buf + sizeof(uint64_t), sizeof(uint64_t));

	/*
	 * open/create the index kv
	 */

	p_s(&tval_before);
	rc = daos_kv_open(coh, oid_kv_index, DAOS_OO_RW, &oh_kv_index, NULL);
	p_e("read", "daos_kv_open_2", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("index kv open failed with %d", rc);
		goto close_kv;
	}

	/*
	 * check if there is an existing array for that store key, and keep its uuid
	 * as well as the uuid of the store container
	 */

	char ref_buf[REFLEN] = "";

	p_s(&tval_before);
	rc = daos_kv_get(oh_kv_index, DAOS_TX_NONE, 0, store_key, &size, NULL, NULL);
	p_e("read", "daos_kv_get_3", &tval_before, &tval_after, &tval_result);

	if (rc == 0 && size == 0) {

		printf("not found.");
		goto close_index_kv;

	} else if (rc != 0) {

		printf("index kv size get failed with %d", rc);
		goto close_index_kv;

	}

	p_s(&tval_before);
	rc = daos_kv_get(oh_kv_index, DAOS_TX_NONE, 0, store_key, &size, ref_buf, NULL);
	p_e("read", "daos_kv_get_4", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("index kv get failed with %d", rc);
		goto close_index_kv;
	}

	memcpy(&(oid_array.hi), ref_buf, sizeof(uint64_t));
	memcpy(&(oid_array.lo), ref_buf + sizeof(uint64_t), sizeof(uint64_t));

	/*
	 * open array object
	 */

	daos_size_t cell_size, csize;

	gettimeofday(tv_aopen, NULL);
	p_s(&tval_before);
	rc = daos_array_open(coh, oid_array, DAOS_TX_NONE, DAOS_OO_RW,
				 &cell_size, &csize, &oh_array, NULL);
	p_e("read", "daos_array_open", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("array open failed with %d", rc);
		goto close_index_kv;
	}

	/*
	 * read array size and allocate buffer
	 */

	daos_size_t array_size;
	p_s(&tval_before);
	rc = daos_array_get_size(oh_array, DAOS_TX_NONE, &array_size, NULL);
	p_e("read", "daos_array_get_size", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("array get size failed with %d", rc);
		goto close_array;
	}

	char *out = NULL;
	p_s(&tval_before);
	out = (char*) realloc(out, array_size * sizeof(char));
	p_e("read", "realloc", &tval_before, &tval_after, &tval_result);

	/*
	 * read array
	 */

	daos_array_iod_t iod;
	d_sg_list_t sgl;
	daos_range_t rg;
	d_iov_t iov;

	iod.arr_nr = 1;
	rg.rg_len = array_size;
	rg.rg_idx = offset;
	iod.arr_rgs = &rg;

	sgl.sg_nr = 1;
	d_iov_set(&iov, out, array_size);
	sgl.sg_iovs = &iov;

	p_s(&tval_before);
	rc = daos_array_read(oh_array, DAOS_TX_NONE, &iod, &sgl, NULL);
	p_e("read", "daos_array_read", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("array read failed with %d", rc);
		goto close_array;
	}

	*rbuf = out;

	*len = (ssize_t) array_size;
	res = (ssize_t) array_size;

close_array:
	p_s(&tval_before);
	rc = daos_array_close(oh_array, NULL);
	p_e("read", "daos_array_close", &tval_before, &tval_after, &tval_result);

	gettimeofday(tv_aclose, NULL);

close_index_kv:
	p_s(&tval_before);
	rc = daos_obj_close(oh_kv_index, NULL);
	p_e("read", "daos_obj_close", &tval_before, &tval_after, &tval_result);
close_kv:
	p_s(&tval_before);
	rc = daos_obj_close(oh_kv, NULL);
	p_e("read", "daos_obj_close_2", &tval_before, &tval_after, &tval_result);
exit:
	return res;

  #else

	daos_obj_id_t oid_array, oid_kv, oid_kv_index;
	daos_handle_t oh_array, oh_kv, oh_kv_index;
	daos_size_t size;

	uuid_t index_co_uuid, store_co_uuid;
	daos_handle_t index_coh, store_coh;

	char co_uuid_buf[1 * UUIDLEN] = "";

	int rc;
	ssize_t res = (ssize_t) -1;

	char index_co_uuid_str[37];
	char store_co_uuid_str[37];

	// profiling
	struct timeval tval_before, tval_after, tval_result;

	daos_oclass_id_t oc_main_kv = str_to_oc(oc_main_kv_str);
	daos_oclass_id_t oc_index_kv = str_to_oc(oc_index_kv_str);
	daos_oclass_id_t oc_store_array = str_to_oc(oc_store_array_str);

	/* 
	 * build id for main kv object
	 */

	oid_kv.hi = 0;
	oid_kv.lo = 0;
	p_s(&tval_before);
	daos_obj_generate_oid(coh, &oid_kv, DAOS_OT_KV_HASHED, oc_main_kv, 0, 0);
	p_e("read", "daos_obj_generate_oid", &tval_before, &tval_after, &tval_result);

	/*
	 * open/create the main kv in the provided container
	 */

	p_s(&tval_before);
	rc = daos_kv_open(coh, oid_kv, DAOS_OO_RW, &oh_kv, NULL);
	p_e("read", "daos_kv_open", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("main kv open failed with %d", rc);
		goto exit;
	}

	/*
	 * check presence of index_key in the main kv
	 */

	p_s(&tval_before);
	rc = daos_kv_get(oh_kv, DAOS_TX_NONE, 0, index_key, &size, NULL, NULL);
	p_e("read", "daos_kv_get", &tval_before, &tval_after, &tval_result);

	if (rc == 0 && size == 0) {

		/*
		 * print error and return
		 */
		printf("not found");
		goto close_kv;

	} else if (rc != 0) {

		printf("main kv size get failed with %d", rc);
		goto close_kv;

	}

	p_s(&tval_before);
	rc = daos_kv_get(oh_kv, DAOS_TX_NONE, 0, index_key, &size, co_uuid_buf, NULL);
	p_e("read", "daos_kv_get_2", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("main kv get failed with %d", rc);
		goto close_kv;
	}

	memcpy(&(index_co_uuid[0]), co_uuid_buf, UUIDLEN);

	/*
	 * open index container
	 */

	p_s(&tval_before);
	if (cc_use) {
		rc = daos_cont_open_cache(poh, index_co_uuid, DAOS_COO_RW, &index_coh);
	} else {
		rc = daos_cont_open(poh, index_co_uuid, DAOS_COO_RW, &index_coh, NULL, NULL);
	}
	p_e("read", "daos_cont_open", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("index container open failed with %d", rc);
		goto close_kv;
	}

	/*
	 * open/create the kv in the index container
	 */

	oid_kv_index.hi = 0;
	oid_kv_index.lo = 0;
	p_s(&tval_before);
	daos_obj_generate_oid(index_coh, &oid_kv_index, DAOS_OT_KV_HASHED, oc_index_kv, 0, 0);
	p_e("read", "daos_obj_generate_oid_2", &tval_before, &tval_after, &tval_result);

	p_s(&tval_before);
	rc = daos_kv_open(index_coh, oid_kv_index, DAOS_OO_RW, &oh_kv_index, NULL);
	p_e("read", "daos_kv_open_2", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("index kv open failed with %d", rc);
		goto close_index_cont;
	}

	/*
	 * check if there is an existing array for that store key, and keep its uuid
	 * as well as the uuid of the store container
	 */

	char ref_buf[REFLEN] = "";

	p_s(&tval_before);
	rc = daos_kv_get(oh_kv_index, DAOS_TX_NONE, 0, store_key, &size, NULL, NULL);
	p_e("read", "daos_kv_get_3", &tval_before, &tval_after, &tval_result);

	if (rc == 0 && size == 0) {

		printf("not found.");
		goto close_index_kv;

	} else if (rc != 0) {

		printf("index kv size get failed with %d", rc);
		goto close_index_kv;

	}

	p_s(&tval_before);
	rc = daos_kv_get(oh_kv_index, DAOS_TX_NONE, 0, store_key, &size, ref_buf, NULL);
	p_e("read", "daos_kv_get_4", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("index kv get failed with %d", rc);
		goto close_index_kv;
	}

	memcpy(&(store_co_uuid[0]), ref_buf, UUIDLEN);
	memcpy(&(oid_array.hi), ref_buf + UUIDLEN, sizeof(uint64_t));
	memcpy(&(oid_array.lo), ref_buf + UUIDLEN + sizeof(uint64_t), sizeof(uint64_t));

	/*
	 * open store container
	 */

	p_s(&tval_before);
	if (cc_use) {
		rc = daos_cont_open_cache(poh, store_co_uuid, DAOS_COO_RW, &store_coh);
	} else {
		rc = daos_cont_open(poh, store_co_uuid, DAOS_COO_RW, &store_coh, NULL, NULL);
	}
	p_e("read", "daos_cont_open_2", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("store container open failed with %d", rc);
		goto close_index_kv;
	}

	/*
	 * open array object
	 */

	daos_size_t cell_size, csize;

	gettimeofday(tv_aopen, NULL);
	p_s(&tval_before);
	rc = daos_array_open(store_coh, oid_array, DAOS_TX_NONE, DAOS_OO_RW,
				 &cell_size, &csize, &oh_array, NULL);
	p_e("read", "daos_array_open", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("array open failed with %d", rc);
		goto close_store_cont;
	}

	/*
	 * read array size and allocate buffer
	 */

	daos_size_t array_size;
	p_s(&tval_before);
	rc = daos_array_get_size(oh_array, DAOS_TX_NONE, &array_size, NULL);
	p_e("read", "daos_array_get_size", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("array get size failed with %d", rc);
		goto close_array;
	}

	char *out = NULL;
	p_s(&tval_before);
	out = (char*) realloc(out, array_size * sizeof(char));
	p_e("read", "realloc", &tval_before, &tval_after, &tval_result);

	/*
	 * read array
	 */

	daos_array_iod_t iod;
	d_sg_list_t sgl;
	daos_range_t rg;
	d_iov_t iov;

	iod.arr_nr = 1;
	rg.rg_len = array_size;
	rg.rg_idx = offset;
	iod.arr_rgs = &rg;

	sgl.sg_nr = 1;
	d_iov_set(&iov, out, array_size);
	sgl.sg_iovs = &iov;

	p_s(&tval_before);
	rc = daos_array_read(oh_array, DAOS_TX_NONE, &iod, &sgl, NULL);
	p_e("read", "daos_array_read", &tval_before, &tval_after, &tval_result);

	if (rc != 0) {
		printf("array read failed with %d", rc);
		goto close_array;
	}

	*rbuf = out;

	*len = (ssize_t) array_size;
	res = (ssize_t) array_size;

close_array:
	p_s(&tval_before);
	rc = daos_array_close(oh_array, NULL);
	p_e("read", "daos_array_close", &tval_before, &tval_after, &tval_result);

	gettimeofday(tv_aclose, NULL);

close_store_cont:
	if (!cc_use) {
		p_s(&tval_before);
		rc = daos_cont_close(store_coh, NULL);
		p_e("read", "daos_cont_close", &tval_before, &tval_after, &tval_result);
	}
close_index_kv:
	p_s(&tval_before);
	rc = daos_obj_close(oh_kv_index, NULL);
	p_e("read", "daos_obj_close", &tval_before, &tval_after, &tval_result);
close_index_cont:
	if (!cc_use) {
		p_s(&tval_before);
		rc = daos_cont_close(index_coh, NULL);
		p_e("read", "daos_cont_close_2", &tval_before, &tval_after, &tval_result);
	}
close_kv:
	p_s(&tval_before);
	rc = daos_obj_close(oh_kv, NULL);
	p_e("read", "daos_obj_close_2", &tval_before, &tval_after, &tval_result);
exit:
	return res;

  #endif

#endif

}
