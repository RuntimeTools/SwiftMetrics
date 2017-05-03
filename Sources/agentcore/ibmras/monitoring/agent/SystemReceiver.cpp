/*******************************************************************************
 * Copyright 2016 IBM Corp.
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


#include "SystemReceiver.h"
#include "../connector/Receiver.h"
#include "../Plugin.h"
#include "Agent.h"
#include "../connector/configuration/ConfigurationConnector.h"
#include <iostream>

namespace ibmras {
namespace monitoring {
namespace agent {

const char* sysRecVersion = "1.0";

int startReceiver() {
	return 0;
}

int stopReceiver() {
	return 0;
}

const char* getVersionSys() {
	return sysRecVersion;
}

SystemReceiver::SystemReceiver() {
	name = "System receiver";
	pull = NULL;
	push = NULL;
	start = ibmras::monitoring::agent::startReceiver;
	stop = ibmras::monitoring::agent::stopReceiver;
	getVersion = getVersionSys;
	type = ibmras::monitoring::plugin::receiver;
	recvfactory = (RECEIVER_FACTORY) ibmras_getSystemReceiver;
	confactory = NULL;
}

SystemReceiver::~SystemReceiver() {
}

void SystemReceiver::receiveMessage(const std::string &id, uint32 size,
		void *data) {

	ibmras::monitoring::agent::Agent* agent =
			ibmras::monitoring::agent::Agent::getInstance();

	// If the topic is "datasources" it means we have had a request
	// to send back the source names and config (one for each bucket) to the client
	if (id == "datasources") {
		if(size <= 0 || data == NULL) {
			return;
		}
		std::string topic((char*)data, size);
		topic += "/datasource";

		ibmras::monitoring::connector::ConnectorManager *conMan =
				agent->getConnectionManager();

		ibmras::monitoring::agent::BucketList* buckets = agent->getBucketList();

		std::vector < std::string > ids = buckets->getIDs();

		for (uint32 i = 0; i < ids.size(); i++) {

			std::string config = agent->getConfig(ids[i]);

			std::stringstream str;
			str << ids[i];
			str << ',';
			str << config;
			str << '\n';
			std::string msg = str.str();

			conMan->sendMessage(topic, msg.length(), (void*) msg.c_str());
		}
	} else if (id == "history") {
		std::string topic((char*) data, size);
		topic += "/history/";
		agent->republish(topic);
	} else if (id == "headless") {
		if(size == 0 || data == NULL) {
			// force immediate update for pull sources
			agent->immediateUpdate();
		} else {
			agent->zipHeadlessFiles((const char*)data);
		}
	}
}

}
}
} /* end namespace agent */

void* ibmras_getSystemReceiver() {
	return new ibmras::monitoring::agent::SystemReceiver();
}

