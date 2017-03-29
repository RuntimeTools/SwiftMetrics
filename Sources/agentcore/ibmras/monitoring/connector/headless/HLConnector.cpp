/*******************************************************************************
 * Copyright 2007-2016 IBM Corp.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *******************************************************************************/

#include <iostream>
#include <fstream>
#include <algorithm>
#include <sstream>
#include <iterator>
#include <cstdio>
#include <cstdlib>
#include <errno.h>

#include <string.h>

#if defined(WINDOWS)
#include <sys/stat.h>
#include "windows.h"
#include "WinBase.h"
#include "direct.h"
#include "io.h"
#define PATHSEPARATOR "\\"
#else  /* Unix platforms */
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#define PATHSEPARATOR "/"
#endif

#include "HLConnector.h"
#include "../../agent/Agent.h"
#include "../../../common/logging.h"
#include "../../../common/MemoryManager.h"
#include "../../../common/util/strUtils.h"
#include "../../../common/util/sysUtils.h"
#include "../../../common/port/Process.h"

#if defined(_WINDOWS)
#define HEADLESS_DECL __declspec(dllexport)	/* required for DLLs to export the plugin functions */
#else
#define HEADLESS_DECL
#endif

namespace ibmras {
namespace monitoring {
namespace connector {
namespace headless {

IBMRAS_DEFINE_LOGGER("headless");

const char* headlessConnVersion = "1.0";

static HLConnector* instance = NULL;
static bool collect = true;

static const char* HEADLESS_TOPIC = "headless";

HLConnector* HLConnector::getInstance() {
	if (!instance) {
		instance = new HLConnector();
	}
	return instance;
}

HLConnector::HLConnector() :
		enabled(false), running(false), filesInitialized(false), seqNumber(
				1), lastPacked(0), times_run(0), startDelay(0) {

	number_runs = 0;
	run_duration = 0;
	startTime = 0;
	files_to_keep = 0;
	run_pause = 0;
	upper_limit = INT_MAX;
	lock = new ibmras::common::port::Lock;
}

HLConnector::~HLConnector() {

}

int HLConnector::start() {

	IBMRAS_DEBUG(debug, ">>>HLConnector::start()");
	ibmras::monitoring::agent::Agent* agent =
			ibmras::monitoring::agent::Agent::getInstance();

	std::string enabledProp = agent->getAgentProperty("headless");
	if (ibmras::common::util::equalsIgnoreCase(enabledProp, "on")) {
		enabled = true;
		collect = true;
		IBMRAS_LOG_1(info, "%s", agent->getVersion().c_str());
	} else {
		enabled = false;
		collect = false;
		return 0;
	}

	// initialise run values (in case of late attach causing multiple runs)
	times_run = 0;
	number_runs = 0;
	createdFiles.clear();

	agent->setHeadlessRunning(true);

	std::string delay = agent->getAgentProperty("headless.delay.start");
	if (delay.length()) {
		collect = false;
		startDelay = atoi(delay.c_str());
	}

	std::string ulString = agent->getAgentProperty("headless.files.max.size");
	if (ulString.length()) {
		upper_limit = atoi(ulString.c_str());
	}

	IBMRAS_DEBUG_1(debug, "upper_limit = %d", upper_limit);


	std::string fkString = agent->getAgentProperty("headless.files.to.keep");
	if (fkString.length()) {
		files_to_keep = atoi(fkString.c_str());
	}

	IBMRAS_DEBUG_1(debug, "files_to_keep = %d", files_to_keep);


	std::string rdString = agent->getAgentProperty("headless.run.duration");
	if (rdString.length()) {
		run_duration = atoi(rdString.c_str());
	}

	IBMRAS_DEBUG_1(debug, "run_duration = %d", run_duration);


	std::string rpString = agent->getAgentProperty(
			"headless.run.pause.duration");
	if (rpString.length()) {
		run_pause = atoi(rpString.c_str());
	}

	IBMRAS_DEBUG_1(debug, "run_pause = %d", run_pause);


	std::string nrString = agent->getAgentProperty(
			"headless.run.number.of.runs");
	if (nrString.length()) {
		number_runs = atoi(nrString.c_str());
	}

	IBMRAS_DEBUG_1(debug, "number_runs = %d", number_runs);

	

	//The temporary files will be written at a temporary directory under the user defined path
	//(or the current directory if the one requested by user could not be created.)
	startNewTempDir();

	// Check the correct number of files have been created
	std::vector<std::string> sourceIDs = agent->getBucketList()->getIDs();
	if (createdFiles.size() != sourceIDs.size()) {
		return -1;
	}

	running = true;

	ibmras::common::port::ThreadData* data =
			new ibmras::common::port::ThreadData(thread);
	data->setArgs(this);
	ibmras::common::port::createThread(data);

	IBMRAS_DEBUG(debug, "<<<HLConnector::start()");

	return 0;
}

void HLConnector::startNewTempDir() {
	ibmras::monitoring::agent::Agent* agent =
			ibmras::monitoring::agent::Agent::getInstance();
	time(&startTime);
	lastPacked = startTime;
	struct tm *startTimeStruct;
	startTimeStruct = ::localtime(&startTime);
	strftime(startDate, 20, "%d%m%y_%H%M%S_", startTimeStruct);

//The default path will be the current directory (where the soft monitored is being run)
	std::string defaultPath;
#if defined(WINDOWS)
	TCHAR cDirectory[MAX_PATH];
	DWORD dwRes;
	dwRes = GetCurrentDirectory(sizeof(cDirectory), cDirectory);
#else
	char cDirectory[FILENAME_MAX];
	getcwd(cDirectory, sizeof(cDirectory));
#endif
	defaultPath = cDirectory;

	std::string outputDir = agent->getAgentProperty(
			"headless.output.directory");
	if (!outputDir.length()) {
		userDefinedPath = defaultPath;
	} else {
		userDefinedPath = outputDir;
		if (!createDirectory(userDefinedPath)) {
			IBMRAS_DEBUG_1(warning, "The directory %s could not be created, using default path", outputDir.c_str());
			userDefinedPath = defaultPath;
		}
	}

	IBMRAS_DEBUG_1(debug, "Path = %s", userDefinedPath.c_str());
	
	//The temporary files will be written at a temporary directory under the user defined path
	tmpPath = userDefinedPath;
	tmpPath.append(PATHSEPARATOR);
	tmpPath.append("tmp_");
	tmpPath.append(startDate);
	createDirectory(tmpPath);

	std::string filePrefix = agent->getAgentProperty("headless.filename");
	if (!filePrefix.length()) {
		userDefinedPrefix = "";
	} else {
		IBMRAS_DEBUG_1(debug, "Prefix = %s", filePrefix.c_str());
		userDefinedPrefix = filePrefix;
	}

	IBMRAS_DEBUG_1(debug, "Prefix = %s", userDefinedPrefix.c_str());

	/***
	 * First we create a vector<string> which will contain the IDs of the datasources,
	 * these names will match the names of the files created by createFile
	 */
	std::vector<std::string> sourceIDs = agent->getBucketList()->getIDs();

	for (std::vector<std::string>::iterator it = sourceIDs.begin();
			it != sourceIDs.end(); ++it) {
		createFile(*it);
	}
	filesInitialized = false;
}

void HLConnector::createFile(const std::string &fileName) {
	IBMRAS_DEBUG(debug, ">>>HLConnector::createFile()");
	std::fstream* file = new std::fstream;

	std::string escapedFile = fileName;
	replace(escapedFile.begin(), escapedFile.end(), '/', '_');
	std::string fullPath = tmpPath;
	fullPath.append(PATHSEPARATOR);
	fullPath.append(escapedFile);

	createdFiles[fullPath] = file;
	expandedIDs[fileName] = fullPath;
	IBMRAS_DEBUG(debug, "<<<HLConnector::createFile()");
}

void HLConnector::sleep(uint32 seconds) {
	unsigned long long currentTime = ibmras::common::util::getMilliseconds();
	unsigned long long sleepTime = currentTime + (seconds * 1000);

	while (running && currentTime < sleepTime) {
		ibmras::common::port::sleep(1);
		currentTime = ibmras::common::util::getMilliseconds();
	}
}

bool HLConnector::createDirectory(std::string& path) {
	IBMRAS_DEBUG(debug, ">>>HLConnector::createDirectory");
	bool created = false;

	const char* pathName = path.c_str();

#if defined(WINDOWS)
	DWORD dirAttr;
	IBMRAS_DEBUG_1(debug, "Creating directory: %s", pathName);
	dirAttr = GetFileAttributes(reinterpret_cast<LPCTSTR>(pathName));

	if(INVALID_FILE_ATTRIBUTES == dirAttr) {
		switch (GetLastError()) {
			case ERROR_PATH_NOT_FOUND:
			IBMRAS_DEBUG(warning, "The directory was not found");
			IBMRAS_DEBUG_1(debug, "Creating directory: %s", pathName);
			if(!CreateDirectory(reinterpret_cast<LPCTSTR>(pathName), NULL)) {
				switch (GetLastError()) {
					//if the directory already exists we will use it instead of the current one.
					case ERROR_ALREADY_EXISTS:
					IBMRAS_DEBUG(warning, "The specified directory already exists.");
					created = true;
					break;
					case ERROR_PATH_NOT_FOUND:
					IBMRAS_DEBUG(warning, "The system cannot find the path specified.");
					break;
				}
			} else {
				created = true;
			}
			break;
			case ERROR_INVALID_NAME:
			IBMRAS_DEBUG(warning, "The filename, directory name, or volume label syntax is incorrect");
			break;
			case ERROR_BAD_NETPATH:
			IBMRAS_DEBUG(warning, "The network path was not found.");
			break;
			default:
			IBMRAS_DEBUG(warning, "The directory could not be found, permissions?.");
			IBMRAS_DEBUG_1(debug, "Creating directory: %s", pathName);
			if(!CreateDirectory(reinterpret_cast<LPCTSTR>(pathName), NULL)) {
				switch (GetLastError()) {
					case ERROR_ALREADY_EXISTS:
					IBMRAS_DEBUG(warning, "The specified directory already exists.");
					created = true;
					break;
					case ERROR_PATH_NOT_FOUND:
					IBMRAS_DEBUG(warning, "The system cannot find the path specified.");
					break;
				}
			} else {
				created = true;
			}
		}

	}else if(FILE_ATTRIBUTE_DIRECTORY == dirAttr) {
		created = true;
	}

#else
	struct stat dir;
	IBMRAS_DEBUG_1(debug, "Pathname...%s\n", pathName);
	if (stat(pathName, &dir)) {
		IBMRAS_DEBUG_1(debug, "Directory does not exist, creating...%s\n", pathName);
		if (mkdir(pathName, S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH)) {
			IBMRAS_DEBUG_1(debug, "Directory could not be created: ", strerror(errno));
			if (EEXIST == errno) {
				IBMRAS_DEBUG_1(debug, "Directory % already existed", pathName);
				created = true;
			}
		} else {
			IBMRAS_DEBUG_1(debug, "Directory %s was created: ", pathName);
			created = true;
		}
	} else {
		IBMRAS_DEBUG(debug, "stat() returned 0, we'll check whether it was an existing directory");
		if (S_ISDIR(dir.st_mode)) {
			created = true;
		}
	}
#endif
	IBMRAS_DEBUG(debug, "<<<HLConnector::createDirectory()");

	return created;
}

int HLConnector::stop() {
	IBMRAS_DEBUG(debug, ">>>HLConnector::stop()");

	running = false;

	if (enabled == false) {
		return 0;
	}

	ibmras::monitoring::agent::Agent* agent =
				ibmras::monitoring::agent::Agent::getInstance();

	// Take lock before packing then clearing the files
	if (!lock->acquire()) {
		if (!lock->isDestroyed()) {

			if (collect) {
				IBMRAS_DEBUG(debug, "Closing files at stop");
				closeFilesAndNotify();
			} else {
				IBMRAS_DEBUG(debug, "collect is false");
			}

		}
		lock->release();
	}

	return 0;
}

int HLConnector::sendMessage(const std::string &sourceId, uint32 size,
		void* data) {

	if (!running || !collect || !enabled) {
		IBMRAS_DEBUG(debug, "<<<HLConnector::sendMessage()[NOT COLLECTING DATA]");
		return 0;
	}
	IBMRAS_DEBUG_1(debug, ">>>HLConnector::sendMessage() %s", sourceId.c_str());

	std::map<std::string, std::string>::iterator it;
	it = expandedIDs.find(sourceId);

	if (it == expandedIDs.end()) {
		return -1;
	}

	if (!lock->acquire()) {
		if (!lock->isDestroyed()) {

			// Ensure we are still running after acquiring the lock
			if (!running || !collect || !enabled ) {
				lock->release();
				return 0;
			}

			std::string currentKey = it->second;
			std::fstream* currentSource = createdFiles[currentKey];

			const char* cdata = reinterpret_cast<const char*>(data);
			IBMRAS_DEBUG_1(debug, "currentKey %s", currentKey.c_str());

			if (!filesInitialized) {
				// Send initialize notification to providers
				ibmras::monitoring::agent::Agent* agent =
						ibmras::monitoring::agent::Agent::getInstance();
				agent->getConnectionManager()->receiveMessage("headless", 0,
						NULL);
				filesInitialized = true;
			}
			if (currentSource->is_open()) {
				IBMRAS_DEBUG(debug, "open");
				std::time_t currentTime;
				time(&currentTime);
				uint32 length = currentSource->tellg();
				if ((length + size > upper_limit)) {
					IBMRAS_DEBUG_1(debug, "SendMessage from = %s", sourceId.c_str());
					IBMRAS_DEBUG_1(debug, "MAX_FILE_SIZE = %d", upper_limit);
					IBMRAS_DEBUG_1(debug, "Current time = %d", currentTime);
					IBMRAS_DEBUG(debug, "Closing files due to max file size reached");
					closeFilesAndNotify();
					startNewTempDir();
				}
			}

			if (!currentSource->is_open()) {
				IBMRAS_DEBUG(debug, "not open");
				currentSource->open(currentKey.c_str(),
						std::ios::out | std::ios::app | std::ios::binary);

				// Get persistent Data eg trace header and write to start of file
				ibmras::monitoring::agent::Agent* agent =
						ibmras::monitoring::agent::Agent::getInstance();
				ibmras::monitoring::agent::Bucket *bucket =
						agent->getBucketList()->findBucket(sourceId);
				if (bucket) {

					uint32 id = 0;
					while (true) {

						const char* persistentData = NULL;
						uint32 persistentDataSize = 0;

						IBMRAS_DEBUG_2(debug, "getting persistent data for %s id %d", sourceId.c_str(), id);
						id = bucket->getNextPersistentData(id,
								persistentDataSize, (void**) &persistentData);
						if (persistentData != NULL && size > 0) {
							currentSource->write(persistentData,
									persistentDataSize);
						} else {
							IBMRAS_DEBUG(debug, "persistent data was Null or 0");
							break;
						}
					}
				}

			}

			if (currentSource->is_open()) {
				IBMRAS_DEBUG_1(debug, "Write: %s", cdata);
				currentSource->write(cdata, size);
			}

			lock->release();
		}
	}
	IBMRAS_DEBUG(debug, "<<<HLConnector::sendMessage()");
	return 0;
}

void HLConnector::closeFilesAndNotify() {
	// Close current files and broadcast a message containing their location
	IBMRAS_DEBUG(info, "Closing files");
	for (std::map<std::string, std::fstream*>::iterator it =
			createdFiles.begin(); it != createdFiles.end(); it++) {

		if ((it->second)->is_open()) {
			(it->second)->close();
		}
	}
	// Send message that files have been created in 'tmpPath' temporary directory
	ibmras::monitoring::agent::Agent* agent = ibmras::monitoring::agent::Agent::getInstance();
	IBMRAS_DEBUG_1(info, "tmpPath: %s", tmpPath.c_str());
	std::string outputDir (tmpPath);
	agent->getConnectionManager()->receiveMessage(ibmras::monitoring::connector::headless::HEADLESS_TOPIC, outputDir.length(), (void*) outputDir.c_str());
}

void HLConnector::lockCloseFilesAndNotify(bool createNewTempDir) {
	if (!lock->acquire()) {
		if (!lock->isDestroyed()) {
			closeFilesAndNotify();
			if(createNewTempDir) {
				startNewTempDir();
			}
		}
		lock->release();
	}
}

void HLConnector::processLoop() {
	IBMRAS_DEBUG(debug, ">> processLoop");
	ibmras::monitoring::agent::Agent* agent =
			ibmras::monitoring::agent::Agent::getInstance();

	if (startDelay) {
		IBMRAS_LOG_1(info,
				"Headless data collection starting with delay of %d minutes",
				startDelay);
		sleep(startDelay * 60);
	}
	IBMRAS_LOG(info, "Headless data collection has started");
	IBMRAS_DEBUG_1(debug, "run_duration = %d", run_duration);
	IBMRAS_DEBUG_1(debug, "number_runs = %d", number_runs);
	if (run_duration) {
		IBMRAS_LOG_1(info, "Each data collection run will last for %d minutes",
				run_duration);
	}
	if (run_pause) {
		IBMRAS_LOG_1(info,
				"Agent will pause for %d minutes between each data collection run",
				run_pause);
	}
	if (number_runs) {
		IBMRAS_LOG_1(info, "Agent will run for %d collections", number_runs);
	}
	if (files_to_keep) {
		IBMRAS_LOG_1(info, "Agent will keep last %d hcd files", files_to_keep);
	}
	IBMRAS_LOG_1(info, "Headless collection output directory is %s",
			userDefinedPath.c_str());

	if (number_runs) {
		IBMRAS_DEBUG_1(debug, "Produce HCDs for %d minutes", run_duration);
		while (running && (times_run < number_runs)) {
				collect = true;
				IBMRAS_DEBUG_2(debug, "We've run %d times and have to run %d in total", times_run, number_runs);
				sleep(run_duration * 60);
				times_run++;
				if (running) {
					lockCloseFilesAndNotify(times_run < number_runs);
				}

				if (run_pause > 0) {
					collect = false;
					IBMRAS_DEBUG_1(warning, "Not producing HCDs for %d minutes", run_pause);
					sleep(run_pause * 60);
				}
		}
		running = false;
		agent->setHeadlessRunning(false);

	} else if (run_duration || run_pause) {
		while (running) {
			collect = true;
			IBMRAS_DEBUG_1(debug, "Produce HCDs for %d minutes", run_duration);
			sleep(run_duration * 60);
			if (running) {
				lockCloseFilesAndNotify(false);
			}

			if (run_pause > 0) {
				collect = false;
				IBMRAS_DEBUG_1(warning, "Rest for %d minutes", run_pause);
				sleep(run_pause * 60);
			}
		}
		agent->setHeadlessRunning(false);
	}

	IBMRAS_DEBUG(debug, "<< processLoop");
}





void* HLConnector::thread(ibmras::common::port::ThreadData* tData) {
	HLConnector* hlc = HLConnector::getInstance();
	hlc->processLoop();
	return NULL;
}

} /*end namespace headless*/
} /*end namespace connector*/
} /*end namespace monitoring*/
} /*end namespace ibmras*/

extern "C" {

HEADLESS_DECL int ibmras_monitoring_plugin_start() {
	return 0;
}

HEADLESS_DECL int ibmras_monitoring_plugin_stop() {
	return 0;
}

HEADLESS_DECL const char* ibmras_monitoring_getVersion() {
	return ibmras::monitoring::connector::headless::headlessConnVersion;
}

bool headlessInitialized = false;

HEADLESS_DECL int ibmras_monitoring_plugin_init(const char* properties) {
	if (!headlessInitialized) {
		headlessInitialized = true;
	}
	return 0;
}

HEADLESS_DECL void* ibmras_monitoring_getConnector(const char* properties) {

	ibmras::common::Properties props;
	props.add(properties);

	std::string enabledProp = props.get("com.ibm.diagnostics.healthcenter.headless");
	if (!ibmras::common::util::equalsIgnoreCase(enabledProp, "on")) {
		return NULL;
	}

	std::string loggingProp = props.get("com.ibm.diagnostics.healthcenter.logging.level");
	ibmras::common::LogManager::getInstance()->setLevel("level", loggingProp);
	loggingProp = props.get("com.ibm.diagnostics.healthcenter.logging.headless");
	ibmras::common::LogManager::getInstance()->setLevel("headless", loggingProp);

	return ibmras::monitoring::connector::headless::HLConnector::getInstance();
}
}
