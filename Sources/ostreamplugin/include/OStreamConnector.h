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


#ifndef ibmras_monitoring_connector_ostreamconnector_h
#define ibmras_monitoring_connector_ostreamconnector_h

#include "../../agentcore/ibmras/monitoring/connector/Connector.h"
#include <iostream>

namespace OStream {

class OStreamConnector: public ibmras::monitoring::connector::Connector {
public:

	OStreamConnector();
	OStreamConnector(std::ostream &outputStream);

	std::string getID() { return "OStreamConnector"; }

	int sendMessage(const std::string &sourceId, uint32 size, void *data);

	void registerReceiver(ibmras::monitoring::connector::Receiver *receiver);

	int start();
	int stop();

	~OStreamConnector();
private:
	std::ostream & output;

};

/* end class Connector */

} /* end OStream monitoring */

#endif /* ibmras_monitoring_connector_ostreamconnector_h */
