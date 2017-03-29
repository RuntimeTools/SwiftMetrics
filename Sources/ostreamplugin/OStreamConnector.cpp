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

#include "OStreamConnector.h"
#include "../agentcore/ibmras/common/logging.h"

#if defined(_WINDOWS)
#define OSTREAMCONNECTOR_DECL __declspec(dllexport)	/* required for DLLs to export the plugin functions */
#else
#define OSTREAMCONNECTOR_DECL
#endif

namespace OStream {

IBMRAS_DEFINE_LOGGER("ostream");

OStreamConnector::OStreamConnector(std::ostream &outputStream) :
		output(outputStream) {
}

int OStreamConnector::sendMessage(const std::string &sourceId, uint32 size,
		void *data) {

	char* charData = reinterpret_cast<char*>(data);
	uint32 i;
	output << "----------------------------------------------------------------------------------------------------------\n";
	output << sourceId << "\n";
	output << "----------------------------------------------------------------------------------------------------------\n";
	for (i = 0; i < size; i++) {
		output.put(charData[i]);
	}
	output << "\n----------------------------------------------------------------------------------------------------------\n";
	return i;
}

void OStreamConnector::registerReceiver(ibmras::monitoring::connector::Receiver *receiver) {

}

int OStreamConnector::start() {
	IBMRAS_DEBUG(info, "Starting ostream connector");
	return 0;
}

int OStreamConnector::stop() {
	IBMRAS_DEBUG(info, "Stopping ostream connector");
	return 0;
}

OStreamConnector::~OStreamConnector() {
}

} /* end namespace monitoring */

extern "C" {
OSTREAMCONNECTOR_DECL int ibmras_monitoring_plugin_start() {
	return 0;
}

OSTREAMCONNECTOR_DECL int ibmras_monitoring_plugin_stop() {
	return 0;
}

OSTREAMCONNECTOR_DECL void* ibmras_monitoring_getConnector(const char* properties) {
	return new OStream::OStreamConnector(std::cout);
}

OSTREAMCONNECTOR_DECL char* ibmras_monitoring_getVersion() {
	return "1.0";
}
}
