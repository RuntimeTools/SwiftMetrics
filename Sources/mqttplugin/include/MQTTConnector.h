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


#ifndef ibmras_monitoring_connector_mqtt_mqttconnector_h
#define ibmras_monitoring_connector_mqtt_mqttconnector_h

#include "../../agentcore/ibmras/monitoring/connector/Connector.h"

extern "C" {
#include "../../paho/include/MQTTAsync.h"
}

namespace ibmras {
namespace monitoring {
namespace connector {
namespace mqttcon {

class MQTTConnector: public ibmras::monitoring::connector::Connector {
public:

	MQTTConnector(const std::string &host, const std::string &port,
			const std::string &user, const std::string &pass,
			const std::string &topicNamespace, const std::string &applicationId);

	int sendMessage(const std::string &sourceId, uint32 size, void *data);

	void registerReceiver(ibmras::monitoring::connector::Receiver *receiver);
	ibmras::monitoring::connector::Receiver* returnReceiver();

	int start();
	int stop();

	virtual ~MQTTConnector();
	std::string getID() {
		return "MQTTConnector";
	}
private:
	bool enabled;
	void createClient(const std::string &id);
	int connect();

	int handleReceivedmessage(char *topicName, int topicLen,
			MQTTAsync_message *message);
	static int messageReceived(void *context, char *topicName, int topicLen,
			MQTTAsync_message *message);
	static void connectionLost(void* context, char* cause);

	void handleOnConnect(MQTTAsync_successData* response);
	static void onConnect(void* context, MQTTAsync_successData* response);
	static void onFailure(void* context, MQTTAsync_failureData* response);

	void sendIdentityMessage();

	std::string brokerHost;
	std::string brokerPort;
	std::string brokerUser;
	std::string brokerPass;

	MQTTAsync mqttClient;
	ibmras::monitoring::connector::Receiver *receiver;

	std::string rootTopic;
	std::string agentTopic;
	std::string agentIdMessage;

	std::string willTopic;
	std::string willMessage;
};

} /* end namespace mqttcon */
}
}
}
#endif /* ibmras_monitoring_connector_mqtt_mqttconnector_h */
