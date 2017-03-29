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

#ifndef ibmras_monitoring_connector_headless_hlconnector_h
#define ibmras_monitoring_connector_headless_hlconnector_h

#include <string>
#include <vector>
#include <map>
#include <ctime>

#include "../Connector.h"
#include "../../agent/BucketList.h"
#include "../Receiver.h"
#include "../../../common/port/ThreadData.h"

namespace ibmras {
namespace monitoring {
namespace connector {
namespace headless {

class HLConnector: public ibmras::monitoring::connector::Connector {
public:

	static HLConnector* getInstance();
	virtual ~HLConnector();
	HLConnector();

	virtual std::string getID() {return "HLConnector"; }
	int sendMessage(const std::string &sourceID, uint32 size, void* data);

	int start();
	int stop();

private:
	static void* thread(ibmras::common::port::ThreadData* tData);
	void processLoop();
	void sleep(uint32 seconds);
	void closeFilesAndNotify();
	void lockCloseFilesAndNotify(bool createNewTempDir);
	void startNewTempDir();

	bool enabled;
	bool running;
	bool filesInitialized;

	int32 seqNumber;
	time_t lastPacked;
	uint32 upper_limit;
	int32 files_to_keep;
	std::map<std::string, std::fstream*> createdFiles;
	std::map<std::string, std::string> expandedIDs;
	ibmras::common::port::Lock* lock;
	int32 run_duration;
	int32 run_pause;
	int32 number_runs;
	std::string userDefinedPath;
	std::string tmpPath;
	std::string userDefinedPrefix;
	int32 times_run;
	std::time_t startTime;
	char startDate[100];
	int startDelay;

	void createFile(const std::string &fileName);
	bool createDirectory(std::string& path);
};

void* runCounterThread(ibmras::common::port::ThreadData* tData);


} /*end namespace headless*/
} /*end namespace connector*/
} /*end namespace monitoring*/
} /*end namespace ibmras*/

#endif /*ibmras_monitoring_connector_headless_hlconnector_h*/
