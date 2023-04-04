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

#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <daos.h>
#include <time.h>
#include <sys/time.h>

#include "daos_field_io.h"

#define PARTLEN 1048576

#define BUFLEN 1024

#define FAIL(fmt, ...)									\
do {													\
	fprintf(stderr, "Process (%s): " fmt " aborting\n", \
		node, ## __VA_ARGS__);							\
	exit(1);											\
} while (0)

#define ASSERT(cond, ...)	\
do {						\
	if (!(cond))			\
		FAIL(__VA_ARGS__);	\
} while (0)

static bool prof = 1;

static void p_s(struct timeval *before) {

	if (prof) gettimeofday(before, NULL);

}

static void p_e(const char *wr, const char *f, int node_id, int client_id,
	 struct timeval *before, struct timeval *after, struct timeval *result) {

	char tabs[BUFLEN] = "\t\t";
	if (prof) {
		if (strlen(f) > 16) tabs[1] = '\0';
		gettimeofday(after, NULL);
		timersub(after, before, result);
		printf("Profiling node %d client %d - daos_field_%s - %s: %s%ld.%06ld\n", 
			node_id, client_id, wr, f, tabs,
			(long int)result->tv_sec, (long int)result->tv_usec);
	}

}

static char node[128] = "unknown";
static daos_handle_t poh, coh;

int main(int argc, char** argv) {

	int rc = 0, size_factor, nrep, unique, n_to_write, hold, zzz, node_id, client_id, i;
	char* index_key, * store_key, * data_path;
	ssize_t r;
	char* pool_uuid, * co_uuid;

	struct timeval tval_before, tval_after, tval_result;

	struct timeval tval_before_all, tval_after_all, tval_result_all;

	if (prof) gettimeofday(&tval_before_all, NULL);

	p_s(&tval_before);

	if (argc != 14) {
		fprintf(stderr, "usage: daos_write POOL_ID CONT_ID INDEX_DICT STORE_DICT DATA_PATH SIZE_FACTOR N_REP UNIQUE N_TO_WRITE HOLD SLEEP NODE_ID CLIENT_ID\n");
		exit(1);
	}

	rc = gethostname(node, sizeof(node));
	ASSERT(rc == 0, "buffer for hostname too small");

	//rc = uuid_parse(argv[1], pool_uuid);
	//ASSERT(rc == 0, "Failed to parse 'Pool uuid': %s", argv[1]);
	pool_uuid = argv[1];

	//rc = uuid_parse(argv[2], co_uuid);
	//ASSERT(rc == 0, "Failed to parse 'Container uuid': %s", argv[2]);
	co_uuid = argv[2];

	index_key = argv[3];

	store_key = argv[4]; 

	data_path = argv[5];

	size_factor = atoi(argv[6]);

	nrep = atoi(argv[7]);

	unique = atoi(argv[8]);

	n_to_write = atoi(argv[9]);

	hold = atoi(argv[10]);

	zzz = atoi(argv[11]);

	node_id = atoi(argv[12]);

	client_id = atoi(argv[13]);

	rc = daos_init();
	ASSERT(rc == 0, "daos_init failed with %d", rc);

	rc = daos_pool_connect(pool_uuid, NULL, DAOS_PC_RW, &poh, NULL, NULL);
	ASSERT(rc == 0, "pool connect failed with %d", rc);

	p_e("write", "init and connect time", node_id, client_id, &tval_before, &tval_after, &tval_result);

	p_s(&tval_before);
	sleep(hold);
	p_e("write", "hold sleep time", node_id, client_id, &tval_before, &tval_after, &tval_result);

	char store_key_new[BUFLEN], * store_key_i;
	int fd;
	char* data = NULL;
	size_t data_len;
	ssize_t buf_len;

	p_s(&tval_before);

	fd = open(data_path, O_RDONLY);
	ASSERT(fd >= 0, "data_path open failed");

	// read in size_factor parts of 1 MiB
	data_len = 0;
	for (i = 0; i < size_factor; i++) {

		data = (char*) realloc(data, (data_len + PARTLEN) * sizeof(char));
		bool done = false;
		size_t part_len = 0;
		while (!done) {
			size_t amount_to_read = PARTLEN - part_len;
			buf_len = read(fd, data + data_len + part_len, amount_to_read);
			ASSERT(buf_len >= 0, "read from data_path failed");
			part_len += buf_len;
			if (buf_len < amount_to_read) {
				rc = lseek(fd, 0, SEEK_SET);
			} else {
				done = true;
			}
		}
		ASSERT(PARTLEN == part_len, "reading part failed");
		data_len += PARTLEN;
		rc = lseek(fd, 0, SEEK_SET);
	}

	struct timeval * tval_before_rep, * tval_after_rep;
	tval_before_rep  = (struct timeval *) malloc(nrep * sizeof(struct timeval));
	tval_after_rep  = (struct timeval *) malloc(nrep * sizeof(struct timeval));
	struct timeval * tval_before_io, * tval_after_io;
	tval_before_io  = (struct timeval *) malloc(nrep * sizeof(struct timeval));
	tval_after_io  = (struct timeval *) malloc(nrep * sizeof(struct timeval));
	struct timeval * tval_before_aopen, * tval_after_aclose;
	tval_before_aopen  = (struct timeval *) malloc(nrep * sizeof(struct timeval));
	tval_after_aclose  = (struct timeval *) malloc(nrep * sizeof(struct timeval));

	p_e("write", "preproc time", node_id, client_id, &tval_before, &tval_after, &tval_result);

	printf("THE POOL IS: %s\n", argv[1]);
	printf("THE CONT IS: %s\n", argv[2]);
	printf("THE INDEX_KEY IS: %s\n", argv[3]);
	printf("THE DATA PATH IS: %s\n", argv[5]);
	//printf("THE DATA TO WRITE IS: %.*s\n", (int) data_len, data);
	printf("THE LENGTH OF THE DATA IS: %llu\n", (unsigned long long) data_len);

	rc = daos_cont_open(poh, co_uuid, DAOS_COO_RW, &coh, NULL, NULL);
	ASSERT(rc == 0, "container open failed with %d", rc);

	cc_init();
	oid_alloc_store_init();

	for (i = 0; i < nrep; i++) {
		if (prof) gettimeofday(&tval_before_rep[i], NULL);

		if (unique == 0) {
			store_key_new[0] = '\0';
			strcat(store_key_new, store_key);
			store_key_new[strlen(store_key) - 2] = '\0';
			sprintf(store_key_new + strlen(store_key_new), 
				",\"uid\":\"%04d%04d\"}", node_id, client_id);
			store_key_i = store_key_new;
		} else {
			store_key_new[0] = '\0';
			strcat(store_key_new, store_key);
			store_key_new[strlen(store_key) - 2] = '\0';
			sprintf(store_key_new + strlen(store_key_new), 
				",\"uid\":\"%04d%04d%04d\"}", node_id, client_id, i % n_to_write);
			store_key_i = store_key_new;
		}

		if (prof) gettimeofday(&tval_before_io[i], NULL);

		r = daos_write(poh, coh, index_key, store_key_i, data, data_len, 0, 
				&tval_before_aopen[i], &tval_after_aclose[i]);

		ASSERT(r >= 0, "daos_write failed with %d", rc);

		if (prof) gettimeofday(&tval_after_io[i], NULL);

		if (i != (nrep - 1) && zzz > 0) {
			sleep(zzz);
		}

		if (prof) gettimeofday(&tval_after_rep[i], NULL);
	}

	oid_alloc_store_fini();
	cc_fini();

	rc = daos_cont_close(coh, NULL);
	ASSERT(rc == 0, "cont close failed");

	p_s(&tval_before);

	free(data);

	char message[BUFLEN] = "";
	struct timeval tval_result_rep, tval_result_io, tval_result_aopenclose;
	for (i = 0; i < nrep; i++) {
		printf("THE ITERATION IS: %d\n", i);

		if (prof) {
			if (i == 0) {
				printf("Timestamp before first IO: %ld.%06ld\n", 
					(long int)tval_before_io[i].tv_sec, (long int)tval_before_io[i].tv_usec);
			}

			sprintf(message, "node %d client %d rep %d ", node_id, client_id, i);

				timersub(&tval_after_aclose[i], &tval_before_aopen[i], &tval_result_aopenclose);
				printf("Profiling %sdaos_field_io daos_write - %s: %s%ld.%06ld\n", 
					  message, "daos_array_open_write_close", "\t",
					  (long int)tval_result_aopenclose.tv_sec, 
					  (long int)tval_result_aopenclose.tv_usec);
				printf("Profiling %sdaos_field_io daos_write - %s: %s%ld.%06ld\n", 
					  message, "daos_array_open timestamp before", "\t",
					  (long int)tval_before_aopen[i].tv_sec, 
					  (long int)tval_before_aopen[i].tv_usec);
				printf("Profiling %sdaos_field_io daos_write - %s: %s%ld.%06ld\n", 
					  message, "daos_array_close timestamp after", "\t",
					  (long int)tval_after_aclose[i].tv_sec, 
					  (long int)tval_after_aclose[i].tv_usec);

			timersub(&tval_after_io[i], &tval_before_io[i], &tval_result_io);
			printf("Profiling node %d client %d - daos_field_write - %s: %s%ld.%06ld\n", 
				node_id, client_id, "IO wc time", "\t\t",
				(long int)tval_result_io.tv_sec, (long int)tval_result_io.tv_usec);

			if (i == (nrep - 1)) {
				printf("Timestamp after last IO: %ld.%06ld\n", 
					(long int)tval_after_io[i].tv_sec, (long int)tval_after_io[i].tv_usec);
			}

			timersub(&tval_after_rep[i], &tval_before_rep[i], &tval_result_rep);
			printf("Profiling node %d client %d - daos_field_write - %s: %s%ld.%06ld\n",
				   node_id, client_id, "rep total wc time", "\t\t",
				   (long int)tval_result_rep.tv_sec, (long int)tval_result_rep.tv_usec);
		}

		printf("DATA WRITTEN SUCCESSFULLY\n");
	}

	free(tval_before_rep);
	free(tval_after_rep);
	free(tval_before_io);
	free(tval_after_io);
	free(tval_before_aopen);
	free(tval_after_aclose);

	p_e("write", "postproc wc time", node_id, client_id, &tval_before, &tval_after, &tval_result);

	p_s(&tval_before);

	rc = daos_pool_disconnect(poh, NULL);
	//ASSERT(rc == 0, "disconnect failed");
	if (rc != 0) {
		printf("WARNING: Pool disconnect failed\n");
	}

	rc = daos_fini();
	//ASSERT(rc == 0, "daos_fini failed with %d", rc);
	if (rc != 0) {
		printf("WARNING: daos_fini failed\n");
	}

	p_e("write", "discon and fini wc time", node_id, client_id, &tval_before, &tval_after, &tval_result);

	if (prof) {
		gettimeofday(&tval_after_all, NULL);
		timersub(&tval_after_all, &tval_before_all, &tval_result_all);
		printf("Profiling node %d client %d - daos_field_write - %s: %s%ld.%06ld\n",
			node_id, client_id, "total wc time", "\t\t",
			(long int)tval_result_all.tv_sec, (long int)tval_result_all.tv_usec);
	}

	return 0;
}
