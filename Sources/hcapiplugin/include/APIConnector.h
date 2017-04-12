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

#ifndef ibmras_monitoring_connector_apiconnector_h
#define ibmras_monitoring_connector_apiconnector_h

#include "../../agentcore/ibmras/monitoring/connector/Connector.h"
#include "AgentExtensions.h"
#include "../../agentcore/ibmras/monitoring/Typesdef.h"

#include <cstring>

#if defined(_WINDOWS)
#define APICONNECTORPLUGIN_DECL __declspec(dllexport)   /* required for DLLs to export the plugin functions */
#else
#define APICONNECTORPLUGIN_DECL
#endif

namespace APIConnector {

extern "C" {
APICONNECTORPLUGIN_DECL void registerListener(void(*)(const char*, unsigned int, void*));
APICONNECTORPLUGIN_DECL void deregisterListener();
APICONNECTORPLUGIN_DECL void sendControl(const char*, unsigned int length, void* message);
}

class APIConnector: public ibmras::monitoring::connector::Connector {
public:

    APIConnector();

    std::string getID() { return "APIConnector"; }

    int sendMessage(const std::string &sourceId, uint32 size, void *data);

	void registerReceiver(ibmras::monitoring::connector::Receiver *receiver);
    void deregisterReceiver();
       
	int start();
    int stop();

    ~APIConnector();

private:

};

/* end class Connector */

namespace plugin {
        agentCoreFunctions api;
        uint32 provid;
	ibmras::monitoring::connector::Receiver *receiver;
}


} /* end APIConnector monitoring */

#endif /* ibmras_monitoring_connector_apiconnector_h */

