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


#ifndef ibmras_monitoring_connector_connectormanager_h
#define ibmras_monitoring_connector_connectormanager_h

#include "Connector.h"
#include "Receiver.h"
#include "../../common/port/ThreadData.h"
#include "../../common/port/Lock.h"
#include <set>
#include <queue>

namespace ibmras{
namespace monitoring {
namespace connector {

class DECL ConnectorManager: public Connector, public Receiver {
public:
	ConnectorManager();
	virtual ~ConnectorManager();

	void addConnector(Connector *connector);
	void removeConnector(Connector *connector);
	void removeAllConnectors();
	Connector* getConnector(const std::string &id);
	
	void addReceiver(Receiver *receiver);
	void removeReceiver(Receiver *receiver);
	void removeAllReceivers();

	int sendMessage(const std::string &sourceId, uint32 size, void *data);
	void receiveMessage(const std::string &id, uint32 size, void *data);

	void processMessage(const std::string &id, uint32 size, void *data);

	int start();
	int stop();

private:
	bool running;
	ibmras::common::port::ThreadData threadData;

	class ReceivedMessage {
	public:
		ReceivedMessage(const std::string &id, uint32 size, void *data);
		virtual ~ReceivedMessage() {}

		const std::string& getId() const {
			return id;
		}

		const std::string& getMessage() const {
			return message;
		}

	private:
		std::string id;
		std::string message;
	};

	std::queue<ReceivedMessage> receiveQueue;
	ibmras::common::port::Lock receiveLock;
	ibmras::common::port::Lock sendLock;

	std::set<Connector*> connectors;
	std::set<Receiver*> receivers;

	void processReceivedMessages();
	void processReceivedMessage(const ReceivedMessage &msg);
	static void* processThread(ibmras::common::port::ThreadData *td);
};
}
}
} /* namespace connector */
#endif /* ibmras_monitoring_connector_connectormanager_h */
