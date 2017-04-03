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


#if defined(_ZOS)
#define  _XOPEN_SOURCE_EXTENDED 1
#endif

#include "MQTTConnector.h"
#include "../agentcore/ibmras/common/logging.h"
#include <string.h>
#include <sstream>
#include "stdlib.h"
#include "time.h"
#include "../agentcore/ibmras/common/Properties.h"
#include "../agentcore/ibmras/common/util/sysUtils.h"
#include "../agentcore/ibmras/common/util/strUtils.h"
#include "../agentcore/ibmras/common/common.h"
#include "../agentcore/ibmras/common/port/Process.h"
#include "../agentcore/ibmras/common/MemoryManager.h"

extern "C" {
#define NO_HEAP_TRACKING
#include "../paho/include/Heap.h"
#undef NO_HEAP_TRACKING
}

#define AGENT_TOPIC_PREFIX "ibm/healthcenter"
#define CLIENT_IDENTIFY_TOPIC AGENT_TOPIC_PREFIX  "/identify"
#define CLIENT_IDENTITY_TOPIC AGENT_TOPIC_PREFIX  "/id"
#define DEFAULT_HOST "localhost"
#define DEFAULT_PORT "1883"

#if defined(_WINDOWS)
#define MQTT_DECL __declspec(dllexport)	/* required for DLLs to export the plugin functions */
#else
#define MQTT_DECL
#endif

namespace ibmras {
namespace monitoring {
namespace connector {
namespace mqttcon {

IBMRAS_DEFINE_LOGGER("mqtt")
;

const char* mqttConnVersion = "1.0";



MQTTConnector::MQTTConnector(const std::string &host, const std::string &port,
		const std::string &user, const std::string &pass,
		const std::string &topicNamespace, const std::string &applicationId) :
		brokerHost(host), brokerPort(port), brokerUser(user), brokerPass(pass), mqttClient(
				NULL) {

	enabled = false;

	int processId = ibmras::common::port::getProcessId();
	unsigned long long time = ibmras::common::util::getMilliseconds();
	srand((unsigned int) time);

	std::stringstream clientIdStream;
	clientIdStream << "agent_" << rand();
	std::string clientId = clientIdStream.str();

	std::string namespacePrefix = topicNamespace;
	if (topicNamespace.length() > 0
			&& topicNamespace[topicNamespace.length() - 1] != '/') {
		namespacePrefix += '/';
	}

	std::stringstream rootTopicStream;
	rootTopicStream << namespacePrefix << AGENT_TOPIC_PREFIX << "/" << clientId;
	rootTopic = rootTopicStream.str();

	std::stringstream agentTopicStream;
	agentTopicStream << namespacePrefix << AGENT_TOPIC_PREFIX << "/agent/"
			<< clientId << "/";
	agentTopic = agentTopicStream.str();

	std::stringstream agentIdMessageStream;
	std::string applicationIdentifier;
	applicationIdentifier = ibmras::common::port::getHostName() + ":";
	applicationIdentifier += ibmras::common::itoa(processId);
	if (applicationId.length() > 0) {
		applicationIdentifier += ":" + applicationId;
	}
	agentIdMessageStream << rootTopic << "\n" << applicationIdentifier;
	agentIdMessage = agentIdMessageStream.str();

	willTopic = rootTopic + "/will";
	willMessage = agentIdMessage;
	createClient(clientId);

	IBMRAS_DEBUG_1(fine, "MQTTConnector: creating client: %s", clientId.c_str());
}

MQTTConnector::~MQTTConnector() {
	if (mqttClient != NULL) {
		MQTTAsync_disconnect(mqttClient, NULL);
		MQTTAsync_destroy(&mqttClient);
	}
}

void MQTTConnector::createClient(const std::string &clientId) {
	if (mqttClient == NULL) {
		std::string address("tcp://");
		address += brokerHost;
		address += ":";
		address += brokerPort;

		// Pass Paho our allocation functions so we can track its memory usage within the rest
		// of the agents memory usage.
		Heap_set_allocator(&ibmras::common::memory::allocate, &ibmras::common::memory::deallocate);

		int rc = MQTTAsync_create(&mqttClient, address.c_str(),
				clientId.c_str(), MQTTCLIENT_PERSISTENCE_NONE, NULL);

		if (rc != MQTTASYNC_SUCCESS) {
			IBMRAS_DEBUG_1(fine, "MQTTConnector: client create failed: %d", rc);
		} else {
			rc = MQTTAsync_setCallbacks(mqttClient, this, connectionLost,
					messageReceived, NULL);
			if (rc != MQTTASYNC_SUCCESS) {
				IBMRAS_DEBUG_1(fine, "MQTTConnector: setCallbacks failed: %d", rc);
			}
		}

	}
}

int MQTTConnector::connect() {
	IBMRAS_DEBUG(fine, "MQTTConnector: connecting");
	int rc = MQTTASYNC_FAILURE;
	if (mqttClient != NULL) {
		if (MQTTAsync_isConnected(mqttClient)) {
			return MQTTASYNC_SUCCESS;
		}

		MQTTAsync_connectOptions connOpts = MQTTAsync_connectOptions_initializer;
		MQTTAsync_willOptions willOpts = MQTTAsync_willOptions_initializer;
		willOpts.message = willMessage.c_str();
		willOpts.topicName = willTopic.c_str();

		connOpts.cleansession = 1;
		connOpts.keepAliveInterval = 20;
		connOpts.onSuccess = onConnect;
		connOpts.onFailure = onFailure;
		connOpts.context = this;
		connOpts.will = &willOpts;

		if (brokerUser != "") {
			connOpts.username = strdup(brokerUser.c_str());
		}
		if (brokerPass != "") {
			connOpts.password = strdup(brokerPass.c_str());
		}

		rc = MQTTAsync_connect(mqttClient, &connOpts);
		if (rc != MQTTASYNC_SUCCESS) {
			IBMRAS_DEBUG_1(fine, "MQTTAsync_connect failed. rc=%d", rc);
		}
	}
	return rc;
}

void MQTTConnector::onConnect(void* context, MQTTAsync_successData* response) {
	((MQTTConnector*) context)->handleOnConnect(response);
}

void MQTTConnector::onFailure(void* context, MQTTAsync_failureData* response) {
	if (response == NULL) {
		IBMRAS_DEBUG(fine, "MQTTAsync_connect failed");
	} else {
		IBMRAS_DEBUG_1(fine, "MQTTAsync_connect failed. rc: %d", response->code);
		if (response->message != NULL) {
			IBMRAS_DEBUG_1(fine, "MQTTAsync_connect failure reason: %s", response->message);
		}
	}
}

void MQTTConnector::handleOnConnect(MQTTAsync_successData* response) {
	IBMRAS_LOG_2(info, "Connected to broker %s:%s", brokerHost.c_str(), brokerPort.c_str());

	char *topic = new char[agentTopic.length() + 2];
#if defined(_ZOS)
#pragma convert("ISO8859-1")
#endif
	sprintf(topic, "%s#", agentTopic.c_str());
#if defined(_ZOS)
#pragma convert(pop)
#endif
	IBMRAS_DEBUG_1(debug, "MQTTAsync_subscribe to %s", topic);
	MQTTAsync_responseOptions opts = MQTTAsync_responseOptions_initializer;
	opts.context = this;
	int rc = MQTTAsync_subscribe(mqttClient, topic, 1, &opts);
	if (rc != MQTTASYNC_SUCCESS) {
		IBMRAS_DEBUG_2(fine, "MQTTAsync_subscribe to %s failed. rc=%d", topic, rc);
	}
	delete[] topic;

	char identifyTopic[] = CLIENT_IDENTIFY_TOPIC;
	IBMRAS_DEBUG_1(debug, "MQTTAsync_subscribe to %s", identifyTopic);
	rc = MQTTAsync_subscribe(mqttClient, identifyTopic, 1, &opts);
	if (rc != MQTTASYNC_SUCCESS) {
		IBMRAS_DEBUG_2(fine, "MQTTAsync_subscribe to %s failed. rc=%d", CLIENT_IDENTIFY_TOPIC, rc);
	} else {
		sendIdentityMessage();
	}
}

void MQTTConnector::connectionLost(void *context, char *cause) {
	IBMRAS_LOG_2(warning, "Connection to broker %s:%s has been lost", ((MQTTConnector*) context)->brokerHost.c_str(), ((MQTTConnector*) context)->brokerPort.c_str());
}

int MQTTConnector::sendMessage(const std::string &sourceId, uint32 size,
		void *data) {

	if (!enabled) {
		return 0;
	}

	if (mqttClient == NULL) {
		return -1;
	}

	if (!MQTTAsync_isConnected(mqttClient)) {
		if (sourceId == "heartbeat") {
			connect();
			return 0;
		} else {
			return -1;
		}
	}

	IBMRAS_DEBUG_3(fine, "Sending message : topic %s : data %p : length %d", sourceId.c_str(), data, size);

	/* topic = <clientId>/sourceId */
	char *topic = new char[rootTopic.length() + 1 + sourceId.length() + 1];
#if defined(_ZOS)
#pragma convert("ISO8859-1")
#endif
	sprintf(topic, "%s/%s", rootTopic.c_str(), sourceId.c_str());
#if defined(_ZOS)
#pragma convert(pop)
#endif

	//	MQTTAsync_deliveryToken token;
	MQTTAsync_send(mqttClient, topic, size, data, 1, 0, NULL);

	delete[] topic;

	return size;
}

int MQTTConnector::messageReceived(void *context, char *topicName, int topicLen,
		MQTTAsync_message *message) {
	return ((MQTTConnector*) context)->handleReceivedmessage(topicName,
			topicLen, message);
}

int MQTTConnector::handleReceivedmessage(char *topicName, int topicLen,
		MQTTAsync_message *message) {

	IBMRAS_DEBUG_1(debug, "MQTT message received for %s", topicName);
	std::string topic(topicName);

	if (topic == CLIENT_IDENTIFY_TOPIC) {
		sendIdentityMessage();
	}
	if (receiver != NULL) {
		if (topic.find(agentTopic) == 0) {
			topic = topic.substr(agentTopic.length());
			IBMRAS_DEBUG_1(debug, "forwarding message %s", topic.c_str());
		}
		receiver->receiveMessage(topic, message->payloadlen, message->payload);
	}

	MQTTAsync_freeMessage(&message);
	MQTTAsync_free(topicName);
	return true;
}

void MQTTConnector::registerReceiver(
		ibmras::monitoring::connector::Receiver *receiver) {
	IBMRAS_DEBUG(debug, "registerReceiver");
	this->receiver = receiver;
}

ibmras::monitoring::connector::Receiver* MQTTConnector::returnReceiver() {
	return receiver;
}

int MQTTConnector::start() {
	IBMRAS_DEBUG(debug, "start");

	IBMRAS_LOG_2(info, "Connecting to broker %s:%s", brokerHost.c_str(), brokerPort.c_str());
	enabled = true;
	return connect();
}

int MQTTConnector::stop() {
	IBMRAS_DEBUG(debug, "stop");

	if (mqttClient != NULL) {
		if (MQTTAsync_isConnected(mqttClient)) {
			// Send will message before our clean termination
			char* message = new char[willMessage.length() + 1];
			strcpy(message, willMessage.c_str());
			MQTTAsync_send(mqttClient, willTopic.c_str(), strlen(message),
					message, 1, 0, NULL);
			delete[] message;

			return MQTTAsync_disconnect(mqttClient, NULL);
		}
	}
	return -1;
}

void MQTTConnector::sendIdentityMessage() {
	IBMRAS_DEBUG_1(debug, "sending identity message: %s", agentIdMessage.c_str());
	char topic[] = CLIENT_IDENTITY_TOPIC;
	char* idMessage = new char[agentIdMessage.length() + 1];
	strcpy(idMessage, agentIdMessage.c_str());
	MQTTAsync_send(mqttClient, topic, strlen(idMessage), idMessage, 1, 0, NULL);
	delete[] idMessage;
}

}
}
}
} /* end mqttcon monitoring */

extern "C" {

#if defined(WINDOWS)
#else
void MQTTAsync_init();
#endif

MQTT_DECL int ibmras_monitoring_plugin_start() {
	return 0;
}

MQTT_DECL int ibmras_monitoring_plugin_stop() {
	return 0;
}

MQTT_DECL const char* ibmras_monitoring_getVersion() {
	return ibmras::monitoring::connector::mqttcon::mqttConnVersion;
}

bool mqttInitialized = false;

MQTT_DECL int ibmras_monitoring_plugin_init(const char* properties) {
	if (!mqttInitialized) {
#if defined(WINDOWS)
#else
		MQTTAsync_init();
#endif
		mqttInitialized = true;
	}
	return 0;
}

MQTT_DECL void* ibmras_monitoring_getConnector(const char* properties) {

	ibmras::common::Properties props;
	props.add(properties);

	std::string enabledProp = props.get("com.ibm.diagnostics.healthcenter.mqtt");
	if (!ibmras::common::util::equalsIgnoreCase(enabledProp, "on")) {
		return NULL;
	}

	std::string loggingProp = props.get("com.ibm.diagnostics.healthcenter.logging.level");
		ibmras::common::LogManager::getInstance()->setLevel("level", loggingProp);
	loggingProp = props.get("com.ibm.diagnostics.healthcenter.logging.mqtt");
	ibmras::common::LogManager::getInstance()->setLevel("mqtt", loggingProp);


	std::string brokerHost = props.get("com.ibm.diagnostics.healthcenter.mqtt.broker.host");
	if (!brokerHost.compare("")) {
		brokerHost = DEFAULT_HOST;
	}

	std::string brokerPort = props.get("com.ibm.diagnostics.healthcenter.mqtt.broker.port");
	if (!brokerPort.compare("")) {
		brokerPort = DEFAULT_PORT;
	}
	std::string brokerUser = props.get("com.ibm.diagnostics.healthcenter.mqtt.broker.user");
	std::string brokerPass = props.get("com.ibm.diagnostics.healthcenter.mqtt.broker.pass");
	std::string topcNamespace = props.get("com.ibm.diagnostics.healthcenter.mqtt.topic.namespace");
	std::string applicationId = props.get("com.ibm.diagnostics.healthcenter.mqtt.application.id");

	return new ibmras::monitoring::connector::mqttcon::MQTTConnector(brokerHost,
			brokerPort, brokerUser, brokerPass, topcNamespace, applicationId);
}
}
