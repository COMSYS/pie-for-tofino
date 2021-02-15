/*
    PIE for Tofino
    Copyright (c) 2021 
	
	Author: Ike Kunze
	E-mail: kunze@comsys.rwth-aachen.de
*/

#include <bf_rt/bf_rt_info.hpp>
#include <bf_rt/bf_rt_init.hpp>
#include <bf_rt/bf_rt_common.h>
#include <bf_rt/bf_rt_table_key.hpp>
#include <bf_rt/bf_rt_table_data.hpp>
#include <bf_rt/bf_rt_table.hpp>
#include <bf_rt/bf_rt_table_operations.hpp>
#include <getopt.h>
#include <cstdlib>
#include <functional>
#include <thread>
#include <sys/socket.h>
#include <netdb.h>
#include <errno.h>
#include <fstream>
#include <stdio.h>
#include <gmpxx.h>
#include <time.h>
#include <iterator>
#include <chrono>
#include <sys/time.h> 

#include <csignal>

#include <iostream>
#include <fstream>
#include <sstream>

#include <signal.h>
#include <stdlib.h>
#include <unistd.h>

//#include <stdio.h>

extern "C" {
	#include <bf_switchd/bf_switchd.h>
}

#define CONTROLLER_PORT "20206"
#define CONTROLLER_ADDR "127.0.0.1"

namespace bfrt {
namespace run_controlplane_pie {

using nanotime = mpz_class;
namespace {

struct action_def {
	bf_rt_id_t id;
	std::unique_ptr<bfrt::BfRtTableData> data_ref;
	std::map<std::string, bf_rt_id_t> data_fields;

	action_def(std::map<std::string, bf_rt_id_t> fields)
		: data_fields(fields)
	{}

	action_def() {};
};


const bfrt::BfRtInfo *bfrtInfo = nullptr;
std::shared_ptr<bfrt::BfRtSession> session;

#define ALL_PIPES 0xffff
bf_rt_target_t device_target;

// Drop Probability Register
const bfrt::BfRtTable* drop_prob_reg;
bf_rt_id_t dpr_index_key_id;
bf_rt_id_t dpr_data_id;

// Drop Probability Register Duplicate (for Debug Output)
const bfrt::BfRtTable* drop_prob_reg_dup;
bf_rt_id_t dpr_index_key_id_dup;
bf_rt_id_t dpr_data_id_dup;

// Delay Register
const bfrt::BfRtTable* delay_reg;
bf_rt_id_t dr_index_key_id;
bf_rt_id_t dr_data_id;

// Drop Count Regsister
const bfrt::BfRtTable* drop_reg;
bf_rt_id_t drop_index_key_id;
bf_rt_id_t drop_data_id;


/* 
 * Define several things related to debug output:
 *
 * 1. config_filename: File which stores general aspects about the initial configuration of PIE
 * 2. stats_filename: This file logs the general stats of PIE, i.e., its drop probability, etc.
 */


std::string config_filename = "/root/pie-stats/config.csv";
const char* stats_filename = "/root/pie-stats/stats.csv";

} // anonymous namespace

/**
 * HELPER FUNCTIONS
 */


void usleepLong(unsigned long long sleepyTime){

	struct timespec tspec;

	tspec.tv_sec = 0;
	tspec.tv_nsec = sleepyTime * 1000;

	nanosleep(&tspec, nullptr);
}

/**
 * MAIN FUNCTIONS
 */

void init() {
	device_target.dev_id = 0;
	device_target.pipe_id = ALL_PIPES;

	auto &devMgr = bfrt::BfRtDevMgr::getInstance();
	// Get bfrtInfo object from dev_id and p4 program name

	printf("Start Controlplane PIE\n");
	auto bf_status = devMgr.bfRtInfoGet(device_target.dev_id, "pie_controlplane", &bfrtInfo);
	// Check for status
	assert(bf_status == BF_SUCCESS);

	// Create a session object
	session = bfrt::BfRtSession::sessionCreate();
}



void init_registers(){

	// Initialize drop_prob register
	auto bf_status = bfrtInfo->bfrtTableFromNameGet("Ingress.drop_prob_reg", &drop_prob_reg);
  	assert(bf_status == BF_SUCCESS);

	bf_status = drop_prob_reg->keyFieldIdGet("$REGISTER_INDEX", &dpr_index_key_id);
	assert(bf_status == BF_SUCCESS);

  	bf_status = drop_prob_reg->dataFieldIdGet("Ingress.drop_prob_reg.f1", &dpr_data_id);
  	assert(bf_status == BF_SUCCESS);


	// Initialize duplicate drop_prob register
	bf_status = bfrtInfo->bfrtTableFromNameGet("Ingress.drop_prob_reg_duplicate", &drop_prob_reg_dup);
  	assert(bf_status == BF_SUCCESS);

	bf_status = drop_prob_reg_dup->keyFieldIdGet("$REGISTER_INDEX", &dpr_index_key_id_dup);
	assert(bf_status == BF_SUCCESS);

  	bf_status = drop_prob_reg_dup->dataFieldIdGet("Ingress.drop_prob_reg_duplicate.f1", &dpr_data_id_dup);
  	assert(bf_status == BF_SUCCESS);


	// Initialize delay register
	bf_status = bfrtInfo->bfrtTableFromNameGet("Egress.delay_reg", &delay_reg);
  	assert(bf_status == BF_SUCCESS);

	bf_status = delay_reg->keyFieldIdGet("$REGISTER_INDEX", &dr_index_key_id);
	assert(bf_status == BF_SUCCESS);

  	bf_status = delay_reg->dataFieldIdGet("Egress.delay_reg.f1", &dr_data_id);
  	assert(bf_status == BF_SUCCESS);
}


uint64_t read_register(const BfRtTable *reg_var, bf_rt_id_t reg_index_key_id, bf_rt_id_t reg_data_id){

	auto flag = bfrt::BfRtTable::BfRtTableGetFlag::GET_FROM_HW;

	std::unique_ptr<BfRtTableKey> reg_key;
	std::unique_ptr<BfRtTableData> reg_data;

	auto bf_status = reg_var->keyAllocate(&reg_key);
	assert(bf_status == BF_SUCCESS);

	bf_status = reg_var->dataAllocate(&reg_data);
	assert(bf_status == BF_SUCCESS);

	uint64_t key = 0;
	bf_status = reg_key->setValue(reg_index_key_id, key);
	assert(bf_status == BF_SUCCESS);

	bf_status = reg_var->tableEntryGet(*session, device_target, *(reg_key.get()),
									flag, reg_data.get());
	assert(bf_status == BF_SUCCESS);

	std::vector<uint64_t> values;
	bf_status = reg_data->getValue(reg_data_id, &values);
	assert(bf_status == BF_SUCCESS);

	return values[1];
}


void write_register(const BfRtTable *reg_var, bf_rt_id_t reg_index_key_id, bf_rt_id_t reg_data_id, uint32_t write_value){

	auto flag = bfrt::BfRtTable::BfRtTableGetFlag::GET_FROM_HW;

	std::unique_ptr<BfRtTableKey> reg_key;
	std::unique_ptr<BfRtTableData> reg_data;

	auto bf_status = reg_var->keyAllocate(&reg_key);
	assert(bf_status == BF_SUCCESS);

	bf_status = reg_var->dataAllocate(&reg_data);
	assert(bf_status == BF_SUCCESS);

	uint64_t key = 0;
	bf_status = reg_key->setValue(reg_index_key_id, key);
	assert(bf_status == BF_SUCCESS);

	bf_status = reg_data->setValue(reg_data_id, (uint64_t) write_value);
	assert(bf_status == BF_SUCCESS);

	bf_status = reg_var->tableEntryAdd(*session, device_target,
									*reg_key.get(), *reg_data.get());
	assert(bf_status == BF_SUCCESS);
}

uint64_t read_delay_reg(){
	return read_register(delay_reg, dr_index_key_id, dr_data_id);	
}

void write_drop_prob_reg(uint32_t write_value){
	write_register(drop_prob_reg, dpr_index_key_id, dpr_data_id, write_value);
}

uint64_t read_drop_prob_reg(){
	return read_register(drop_prob_reg, dpr_index_key_id, dpr_data_id);
}

void write_drop_prob_reg_dup(uint32_t write_value){
	write_register(drop_prob_reg_dup, dpr_index_key_id_dup, dpr_data_id_dup, write_value);
}




bool LOOP_RUNNING = true;

void stopTheMainLoop(int sig_num) {
   std::cout << "Interrupt signal (" << sig_num << ") received.\n";
   LOOP_RUNNING = false;
}



void main_thread() {
	printf("##########################################\n");
	printf("CPP - Start Controlplane! \n");
	printf("##########################################\n");
	printf("Starting main thread...\n");
	printf("Trying to connect to control server...\n");
	int sockfd, rv, numbytes;

	char buffer[1024];
	std::string recv_string;

	struct addrinfo hints, *info;
	hints.ai_family = AF_INET;
	hints.ai_socktype = SOCK_STREAM;
	hints.ai_protocol = IPPROTO_IP;

	if ((rv = getaddrinfo(CONTROLLER_ADDR, CONTROLLER_PORT, &hints, &info)) != 0) {
        printf("getaddrinfo: %s\n", gai_strerror(rv));
        return;
    }

	sockfd = socket(info->ai_family, info->ai_socktype, info->ai_protocol);
	if (sockfd == -1) {
		perror("Error while creating socket");
		return;
	}

	printf("Connected!\n");

	struct sigaction sigHandler;

	sigHandler.sa_handler = stopTheMainLoop;
	sigemptyset(&sigHandler.sa_mask);
	sigHandler.sa_flags = 0;

	sigaction(SIGINT, &sigHandler, NULL);
	sigaction(SIGTERM, &sigHandler, NULL);
	sigaction(SIGHUP, &sigHandler, NULL);


	double MS_TO_US = 1000.0;
	double S_TO_US = 1000000.0;
	double US = 1.0;
	double T_UPDATE=15 * MS_TO_US;
	double QDELAY_REF=15 * MS_TO_US;

	uint32_t MAX_PROB= 4294967295;//   2**32-1;
	double alpha=0.125;
	double beta=1.25;

	double QDELAY_REF_NEU = 125*US;
	double T_UPDATE_NEU = 150*US;

	while (T_UPDATE > T_UPDATE_NEU){
		T_UPDATE = T_UPDATE / 2.0;
		beta= beta+alpha/4.0;
		alpha=alpha/2.0;
	}

	alpha = alpha * QDELAY_REF/QDELAY_REF_NEU;
	beta = beta * QDELAY_REF/QDELAY_REF_NEU;

	double alpha_scaled = alpha * (MAX_PROB/S_TO_US);
	double beta_scaled = beta * (MAX_PROB/S_TO_US);


	std::ofstream configFile (config_filename);
	if (configFile.is_open()){
		configFile << ",T_Update, DelayRef, Alpha, Beta\n";
		configFile << " Chosen, " << T_UPDATE << "," << QDELAY_REF_NEU << "," << alpha_scaled << "," << beta_scaled;
		configFile.close();
	}

	std::ofstream statsFile (stats_filename);
	if (statsFile.is_open()){
		std::cout << "Stats output file is ready\n";
		statsFile << "timestamp_us, queue_delay_ns, drop_prob\n";
	}
			
	double drop_probability = 0;

	double queue_delay = 0;
	double queue_delay_old = 0;

	double drop_prob_update = 0.0;

	double packets_dropped = 0.0;


	auto flag = bfrt::BfRtTable::BfRtTableGetFlag::GET_FROM_HW;


	bool firstTime = true;
	
	struct timeval temp_timeVal;
	unsigned long long oldIteration_timeUs, newIteration_timeUs;

	unsigned long long timeDifferenceUs;


	unsigned long long desiredIntervalUs = 117;	
	unsigned long loopCounter = 0;

	while (LOOP_RUNNING) {


		if (firstTime){
			firstTime = false;

			gettimeofday(&temp_timeVal, NULL);

			newIteration_timeUs = temp_timeVal.tv_usec;
			oldIteration_timeUs = temp_timeVal.tv_usec;
		} else{

			gettimeofday(&temp_timeVal, NULL);

			newIteration_timeUs = temp_timeVal.tv_usec;
			timeDifferenceUs = newIteration_timeUs - oldIteration_timeUs;
			oldIteration_timeUs = newIteration_timeUs;
		}



		if (timeDifferenceUs < desiredIntervalUs){

			unsigned long long sleepTimeLong = desiredIntervalUs-timeDifferenceUs;
			usleepLong(sleepTimeLong);

		} 


		queue_delay = (double) read_delay_reg();

		drop_prob_update = alpha_scaled * (queue_delay - QDELAY_REF_NEU) + beta_scaled * (queue_delay - queue_delay_old);

		if (drop_probability < 0.000001 * (float) MAX_PROB){
			drop_prob_update /= 2048;
		}
		else if (drop_probability < 0.00001 * (float) MAX_PROB){
			drop_prob_update /= 512;
		}
		else if (drop_probability < 0.0001 * (float) MAX_PROB){
			drop_prob_update /= 128;
		}
		else if (drop_probability < 0.001 * (float) MAX_PROB){
			drop_prob_update /= 32;
		}
		else if (drop_probability < 0.01 * (float) MAX_PROB){
			drop_prob_update /= 8;
		}
		else if (drop_probability < 0.1 * (float) MAX_PROB){
			drop_prob_update /= 2;
		}

		drop_probability += drop_prob_update;
		queue_delay_old = queue_delay;

		if (queue_delay == 0 && queue_delay_old == 0){
			drop_probability = drop_probability * 0.98;
		}

		if (drop_probability < 0){
			drop_probability = 0;
		}
		else if (drop_probability > (double) MAX_PROB){
			drop_probability = (double) MAX_PROB;
		}

		// Write the drop probability
		write_drop_prob_reg((uint32_t) drop_probability);
		write_drop_prob_reg_dup((uint32_t) drop_probability);

		session->sessionCompleteOperations();

		struct timeval timeStamp;
		gettimeofday(&timeStamp, NULL);

		unsigned long long us = timeStamp.tv_usec;
		
		std::string timestampString = std::to_string(us);


		if (statsFile.is_open()){
			statsFile << timestampString << "," << queue_delay << "," << drop_probability << "\n";
			statsFile.flush();
		}else{
			std::cout << "Something wrong with the stats file." << std::endl;
		}
	}


	std::cout << "Correctly shutdown Controlplane" << std::endl;
	statsFile.flush();
	statsFile.close();
}

} // run_controlplane_pie
} // bfrt

static void parse_options(bf_switchd_context_t *switchd_ctx, int argc, char **argv) {
	int option_index = 0;

	char* sde_path = std::getenv("SDE");
	printf("The SDE path is: %s \n",sde_path);
	if (sde_path == nullptr) {
		printf("$SDE variable is not set\n");
		//printf(sde_path);
		exit(0);
	}

	static struct option options[] = {
		{"help", no_argument, 0, 'h'}
		// {"program", required_argument, 0, 'p'}
	};

	while (1) {
		int c = getopt_long(argc, argv, "hp:", options, &option_index);

		if (c == -1) {
			break;
		}
		
		switch (c) {
			case 'p':
				char conf_path[256];
				sprintf(conf_path, "%s/build/p4-build/%s/tofino/%s/%s.conf", sde_path, optarg, optarg, optarg);

				switchd_ctx->conf_file = strdup(conf_path);
				printf("Conf-file : %s\n", switchd_ctx->conf_file);
			break;
			case 'h':
			case '?':
				printf("run_controlplane_pie \n");
				printf("Usage : run_controlplane_pie -p <name of the program>\n");
				exit(c == 'h' ? 0 : 1);
			break;
			default:
				printf("Invalid option\n");
				exit(0);
			break;
		}

	}

	if (switchd_ctx->conf_file == NULL) {
		printf("ERROR : -p must be specified\n");
		exit(0);
	}

	char install_path[256];
	sprintf(install_path, "%s/install", sde_path);

	switchd_ctx->install_dir = strdup(install_path);
	printf("Install Dir: %s\n", switchd_ctx->install_dir);
}

int main(int argc, char **argv) {
	printf("Start\n");
	bf_switchd_context_t *switchd_ctx;
	if ((switchd_ctx = (bf_switchd_context_t *)calloc( 1, sizeof(bf_switchd_context_t))) == NULL) {
		printf("Cannot Allocate switchd context\n");
		exit(1);
	}

	parse_options(switchd_ctx, argc, argv);

	switchd_ctx->dev_sts_thread = true;
	switchd_ctx->dev_sts_port = 7777;

	printf("Give status next\n");
	bf_status_t status = bf_switchd_lib_init(switchd_ctx);

	printf("Status: %s\n", bf_err_str(status));

	// Do initial set up
	printf("-------------- Do Init ---------------- \n");
	bfrt::run_controlplane_pie::init();
	// Do table level set up
	printf("-------------- Do Init Registers --------------\n");
	bfrt::run_controlplane_pie::init_registers();

	// Start main thread
	std::thread main_thread(bfrt::run_controlplane_pie::main_thread);

	main_thread.join();

	printf("Main thread exited!\n");

	return 0;
}
