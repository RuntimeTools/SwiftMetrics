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

#include "APIConnector.h"
#include "../agentcore/ibmras/common/util/strUtils.h"
#include "../agentcore/ibmras/common/MemoryManager.h"

#define DEFAULT_CAPACITY 1024000  /* default bucket capacity = 1MB */

#if defined(_WINDOWS)
#define APICONNECTORPLUGIN_DECL __declspec(dllexport)   /* required for DLLs to export the plugin functions */
#else
#define APICONNECTORPLUGIN_DECL
#endif

namespace APIConnector {

const char* apiConnVersion = "1.0";

APIConnector::APIConnector() {
}

void (*listener)(const char*, unsigned int, void*);

int APIConnector::sendMessage(const std::string &sourceId, uint32 size, void *data) {
	if (listener != NULL) {
		char* asciiString = ibmras::common::util::createAsciiString(sourceId.c_str());
		listener(asciiString, size, data);
		ibmras::common::memory::deallocate((unsigned char**)&asciiString);
	}
	return size;
}

extern "C" {
APICONNECTORPLUGIN_DECL void registerListener(void(*func)(const char *, unsigned int, void*)){
	listener = func;
}

APICONNECTORPLUGIN_DECL void deregisterListener(){
    listener = NULL;
}

APICONNECTORPLUGIN_DECL void pushData(const char *sendData) {
    monitordata data;
    data.persistent = false;
    data.provID = plugin::provid;
    data.sourceID = 0;
    data.size = strlen(sendData); // should data->size be a size_t?
    data.data = sendData;
    plugin::api.agentPushData(&data);
}

APICONNECTORPLUGIN_DECL void sendControl(const char* topic, unsigned int length, void* message) {
	char* nativeString = ibmras::common::util::createNativeString(topic);
	plugin::receiver->receiveMessage(std::string(nativeString), length, message);
	ibmras::common::memory::deallocate((unsigned char**)&nativeString);
}

} // end extern C

void APIConnector::registerReceiver(ibmras::monitoring::connector::Receiver *receiver) {
	plugin::receiver = receiver;
}

int APIConnector::start() {
    return 0;
}

int APIConnector::stop() {
    return 0;
}

APIConnector::~APIConnector() {
}

static char* NewCString(const std::string& s) {
    char *result = new char[s.length() + 1];
    std::strcpy(result, s.c_str());
    return result;
}

pushsource* createPushSource(uint32 srcid, const char* name) {
    pushsource *src = new pushsource();
    src->header.name = name;
    std::string desc("Description for ");
    desc.append(name);
    src->header.description = NewCString(desc);
    src->header.sourceID = srcid;
    src->next = NULL;
    src->header.capacity = DEFAULT_CAPACITY;
    return src;
}


extern "C" {
APICONNECTORPLUGIN_DECL pushsource* ibmras_monitoring_registerPushSource(agentCoreFunctions api, uint32 provID) {
    plugin::api = api;
    plugin::api.logMessage(debug, "[api_push] Registering push sources");
    pushsource *head = createPushSource(0, "api");
    plugin::provid = provID;
    return head;
}

APICONNECTORPLUGIN_DECL void* ibmras_monitoring_getConnector(const char* properties) {
	listener = NULL;
    return new APIConnector();
}

APICONNECTORPLUGIN_DECL int ibmras_monitoring_plugin_start() {
    return 0;
}

APICONNECTORPLUGIN_DECL int ibmras_monitoring_plugin_stop() {
    return 0;
}

APICONNECTORPLUGIN_DECL const char* ibmras_monitoring_getVersion() {
	return apiConnVersion;
}

}   // extern "C"

}   // Listener namespace
