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


/*
 * Main agent functionality
 */

#include <iostream>
#include <vector>
#include <string>

#include "Agent.h"
#include "../../common/logging.h"
#include "threads/ThreadPool.h"
#include "../../common/PropertiesFile.h"
#include "../../common/LogManager.h"
#include "SystemReceiver.h"
#include "../AgentExtensionReceiver.h"
#include "../../common/util/strUtils.h"


#if defined(WINDOWS)
const char PATHSEPARATOR = '\\';
const char* LIBPREFIX = "";
const char* LIBSUFFIX = ".dll";
#define AGENT_DECL __declspec(dllexport)
#else
#define AGENT_DECL
const char PATHSEPARATOR = '/';
const char* LIBPREFIX = "lib";
#if defined(AIX)
const char* LIBSUFFIX = ".a";
#else
const char* LIBSUFFIX = ".so";
#endif
#endif

namespace ibmras {
namespace monitoring {
namespace agent {
ibmras::common::Logger* pluginlogger = (ibmras::common::Logger*)ibmras_common_LogManager_getLogger( "plugins" );
ibmras::common::Logger* corelogger = (ibmras::common::Logger*)ibmras_common_LogManager_getLogger( "loader" );
}
}
}

//THIS IS THE EXTERNAL FUNCTION THAT WILL BE LOOKED FOR BY THE LOADER
//--------------------------------------------------------------------
extern "C" {
AGENT_DECL loaderCoreFunctions* loader_entrypoint() {

	loaderCoreFunctions* lCF = new loaderCoreFunctions;

	lCF->init = initWrapper;
	lCF->initialize = initWrapper;
	lCF->start = startWrapper;
	lCF->stop = stopWrapper;
	lCF->shutdown = shutdownWrapper;
	lCF->getProperty = getPropertyWrapper;
	lCF->setProperty = setPropertyWrapper;
	lCF->logMessage = logCoreMessageWrapper;
	lCF->loadPropertiesFile = loadPropertiesFileWrapper;
	lCF->getAgentVersion = getVersionWrapper;
	lCF->setLogLevels = setLogLevelsWrapper;
	lCF->registerZipFunction = registerZipFunctionWrapper;
    lCF->addPlugin = addPluginWrapper;

	return lCF;
}

const char* getPropertyWrapper(const char * key) {
	return ibmras::monitoring::agent::getPropertyImpl(key);
}

void setPropertyWrapper(const char* key, const char* value) {
	ibmras::monitoring::agent::setPropertyImpl(key, value);
}

//THESE ARE THE IMPLEMENTATIONS FOR THE FUNCTIONS THAT GET EXPOSED THRU THE API (PLUGINS)
//---------------------------------------------------------------------------------------

/* This is the function callback a plugin gets to send data
 * to its bucket
 */
void pushDataWrapper(monitordata* data) {
	ibmras::monitoring::agent::Agent::getInstance()->addData(data);
}

int sendMessageWrapper(const char *sourceId, uint32 size, void *data) {
	return ibmras::monitoring::agent::Agent::getInstance()->getConnectionManager()->sendMessage(std::string(sourceId), size, data);
}

/* This is the function callback that a plugin will get if
 * they want to log a message.
 */
void logMessageWrapper(loggingLevel lev, const char * message){
	ibmras::monitoring::agent::pluginlogger->log(lev, message);
}

//THESE ARE THE IMPLEMENTATIONS FOR THE FUNCTIONS THAT GET EXPOSED THRU THE API (CORE)
//---------------------------------------------------------------------------------------

void initWrapper() {
	ibmras::monitoring::agent::Agent::getInstance()->init();
}

void startWrapper() {
	ibmras::monitoring::agent::Agent::getInstance()->start();
}

void stopWrapper() {
	ibmras::monitoring::agent::Agent::getInstance()->stop();
}

void shutdownWrapper() {
	ibmras::monitoring::agent::Agent::getInstance()->shutdown();
}

void setLogLevelsWrapper() {
	ibmras::monitoring::agent::Agent::getInstance()->setLogLevels();
}

const char* getVersionWrapper() {
	const char * retString = ibmras::common::util::createAsciiString(ibmras::monitoring::agent::Agent::getInstance()->getVersion().c_str());
	return retString;
}

void logCoreMessageWrapper(loggingLevel lev, const char * message){
	ibmras::monitoring::agent::corelogger->log(lev, message);
}

bool loadPropertiesFileWrapper(const char* fileName) {
	return ibmras::monitoring::agent::Agent::getInstance()->loadPropertiesFile(fileName);
}

void registerZipFunctionWrapper(void(*zipFunc)(const char*)) {
	return ibmras::monitoring::agent::Agent::getInstance()->registerZipFunction(zipFunc);
}

void addPluginWrapper(const char* completeLibraryPath) {
	return ibmras::monitoring::agent::Agent::getInstance()->addPlugin(completeLibraryPath);
}

} // extern "C"

//--------------------------------------------------------------------

namespace ibmras {
namespace monitoring {
namespace agent {

static const char* PROPERTIES_PREFIX = "com.ibm.diagnostics.healthcenter.";
static const char* HEARTBEAT_TOPIC = "heartbeat";

bool running = false;
bool updateNow = false;
bool headlessRunning = false;

Agent* instance = new Agent;
agentCoreFunctions aCF;

//Agent* agentInstance = ibmras::monitoring::agent::Agent::getInstance();

IBMRAS_DEFINE_LOGGER("Agent");

Agent::Agent() {
	activeThreadCount = 0;
}

void Agent::setLogOutput(ibmras::common::LOCAL_LOGGER_CALLBACK func) {
	ibmras::common::LogManager::localLogFunc = func;
}

std::string Agent::getBuildDate() {
	return __DATE__ " " __TIME__;
}

std::string Agent::getVersion() {
	return "3.2.0";
}

void Agent::setLogLevels() {

	std::string loggingPropertyPrefix = PROPERTIES_PREFIX;
	loggingPropertyPrefix +="logging.";

	ibmras::common::LogManager* logMan = ibmras::common::LogManager::getInstance();
	std::list<std::string> keys = properties.getKeys(loggingPropertyPrefix);
	for (std::list<std::string>::iterator i = keys.begin(); i != keys.end();
			++i) {
		std::string component = i->substr(loggingPropertyPrefix.length());
		if (component.length() > 0) {
			std::string value = properties.get(*i);
			loggingLevel lev = none;
			if (value.compare("warning") == 0) {
				lev = warning;
			} else if (value.compare("info") == 0) {
				lev = info;
			} else if (value.compare("fine") == 0) {
				lev = fine;
			} else if (value.compare("finest") == 0) {
				lev = finest;
			} else if (value.compare("debug") == 0) {
				lev = debug;
			} else {
				lev = none;
			}
			logMan->setLevel(component, lev);
		}
	}

}

void Agent::setLocalLog(bool local) {
	ibmras::common::LogManager::getInstance()->localLog = local;
}

DataSourceList<pullsource> Agent::getPullSources() {
	return pullSourceList;
}

DataSourceList<pushsource> Agent::getPushSources() {
	return pushSourceList;
}

DataSource<pullsource>* Agent::getPullSource(std::string uniqueID) {
	Agent* agent = Agent::getInstance();
	uint32 pullcount = agent->getPullSources().getSize();
	for (uint32 i = 0; i < pullcount; i++) {
		DataSource<pullsource> *dsrc = agent->getPullSources().getItem(i);
		if (dsrc->getUniqueID().compare(uniqueID) == 0) {
			return dsrc;
		}
	}
	return NULL;
}

DataSource<pushsource>* Agent::getPushSource(std::string uniqueID) {
	Agent* agent = Agent::getInstance();
	uint32 pushcount = agent->getPushSources().getSize();
	for (uint32 i = 0; i < pushcount; i++) {
		DataSource<pushsource> *dsrc = agent->getPushSources().getItem(i);
		if (dsrc->getUniqueID().compare(uniqueID) == 0) {
			return dsrc;
		}
	}
	return NULL;
}

//THESE ARE THE IMPLEMENTATIONS FOR THE FUNCTIONS THAT GET EXPOSED THRU THE API (PLUGINS)
//---------------------------------------------------------------------------------------

/* This is the function callback a plugin gets to send data
 * to its bucket
 */
//void pushDataImpl(monitordata* data) {
//	Agent* agent = Agent::getInstance();
//	agent->addData(data);
//}
//
//int sendMessageWrapper(const char *sourceId, uint32 size, void *data) {
//	return instance->getConnectionManager()->sendMessage(std::string(sourceId), size, data);
//}
//
///* This is the function callback that a plugin will get if
// * they want to log a message.
// */
//void logMessageImpl(loggingLevel lev, const char * message){
//	pluginlogger->log(lev, message);
//}

//THIS IMPLEMENTATION IS SHARED BETWEEN THE API EXPOSED TO PLUGINS AND THE ONE EXPOSED TO LOADERS
//-----------------------------------------------------------------------------------------------
const char* getPropertyImpl(const char * key){
	std::string property = Agent::getInstance()->getProperty(std::string(key));
	const char * retString = ibmras::common::util::createAsciiString(property.c_str());
	return retString;
}

//WE CAN EXPOSE THIS IN THE FUTURE IF WE WANT TO, SO THE PLUGINS CAN ALSO SET PROPERTIES
//--------------------------------------------------------------------------------------
void setPropertyImpl(const char* key, const char* value) {
	
	Agent::getInstance()->setProperty(key, value);

}


/* thread entry point for publishing data from buckets to the registered connector */
void* processPublishLoop(ibmras::common::port::ThreadData* param) {
	IBMRAS_DEBUG(info, "Starting agent publishing loop");
	Agent* agent = Agent::getInstance();
	std::string headless = agent->getAgentProperty("headless");

	int count = 0;
	while (running) {
		ibmras::common::port::sleep(2);
		agent->publish();

		if (!headless.compare("on") && !agent->isHeadlessRunning()) {
			running = false;
			agent->stop();
		}

		// Send heartbeat ping every 20 seconds
		if (++count > 10) {
			count = 0;
			agent->getConnectionManager()->sendMessage(HEARTBEAT_TOPIC, 0, NULL);
		}

	}
	IBMRAS_DEBUG(info, "Exiting agent publishing loop");
	return NULL;
}

void* endPullSourceLoop(ibmras::common::port::ThreadData* data) {
	Agent* agent = Agent::getInstance();
	agent->threadStop();
	return NULL;
}

void* processPullSourceLoop(ibmras::common::port::ThreadData* data) {
  if(running) {
    Agent* agent = Agent::getInstance();

    if(!agent->startupLock.acquire()) {
	    uint32 pullcount = agent->getPullSources().getSize();

	    ibmras::monitoring::agent::threads::ThreadPool pool;

	    for (uint32 i = 0; i < pullcount; i++) {
		    DataSource<pullsource> *dsrc = agent->getPullSources().getItem(i);
		    if (!(dsrc->getSource()->callback && dsrc->getSource()->complete)) {
			    IBMRAS_DEBUG_1(warning, "Pull source %s disabled due to missing callback or complete function",
					    dsrc->getUniqueID().c_str());
		    } else {
			    pool.addPullSource(dsrc->getSource());
		    }
	    }

	    IBMRAS_DEBUG(info, "Starting agent process pull source loop");

	    pool.startAll();
      agent->startupLock.release();
	    while (running) {
		    ibmras::common::port::sleep(1); /* polling interval for thread */
		    if (running) {
			    pool.process(updateNow); /* process the pull sources */
			    updateNow = false;
		    }
	    }

    #if defined(_WINDOWS) || defined(_ZOS)
	    pool.stopAll();
	    agent->threadStop();
    #endif

	    IBMRAS_DEBUG(info, "Exiting agent process pull source loop");
	    ibmras::common::port::exitThread(NULL);
    }
  }
	return NULL;
}

void Agent::immediateUpdate() {
	updateNow = true;
}

void Agent::publish() {
	bucketList.publish(connectionManager);
}

void Agent::republish(const std::string &topicPrefix) {
	bucketList.republish(topicPrefix, connectionManager);
}


void Agent::addPushSource(std::vector<ibmras::monitoring::Plugin*>::iterator i,
		uint32 provID) {
	if ((*i)->push) {
		pushsource *push = (*i)->push(aCF, provID);
		if (push) {
			IBMRAS_DEBUG(debug, "Push sources were defined");
			pushSourceList.add(provID, push, (*i)->name);
			IBMRAS_DEBUG_1(debug, "Push source list size now : %d",
					pushSourceList.getSize());
			IBMRAS_DEBUG(debug, pushSourceList.toString().c_str());
		} else {
			IBMRAS_DEBUG(info, "No sources were defined !");
		}
	}
}

void Agent::addPullSource(std::vector<ibmras::monitoring::Plugin*>::iterator i,
		uint32 provID) {
	if ((*i)->pull) {
		pullsource *pull = (*i)->pull(aCF,provID);
		if (pull) {
			IBMRAS_DEBUG(debug, "Pull sources were defined");
			pullSourceList.add(provID, pull, (*i)->name);
			IBMRAS_DEBUG_1(info, "Pull source list size now : %d",
					pullSourceList.getSize());
			IBMRAS_DEBUG(debug, pullSourceList.toString().c_str());
		} else {
			IBMRAS_DEBUG(info, "No pull sources were defined !");
		}
	}
}

/*
 * Add a bucket to the overall list of data buckets
 */
void Agent::createBuckets() {
	IBMRAS_DEBUG(fine, "Creating buckets");
	bucketList.add(pushSourceList.getBuckets());
	bucketList.add(pullSourceList.getBuckets());
}

void Agent::addPlugin(ibmras::monitoring::Plugin* plugin) {
	if (plugin) {
		IBMRAS_DEBUG_1(info, "Adding plugin %s", plugin->name.c_str());
    IBMRAS_DEBUG_4(info, "Push source %p, Pull source %p, start %p, stop %p",
				plugin->push, plugin->pull, plugin->start, plugin->stop);
		IBMRAS_LOG_2(fine, "%s, version %s", (plugin->name).c_str(), (plugin->getVersion()));
		plugins.push_back(plugin);
		IBMRAS_DEBUG(info, "Plugin added");
	} else {
		IBMRAS_DEBUG(warning, "Attempt to add null plugin");
	}
}

void Agent::addPlugin(const std::string &dir, const std::string library) {
	ibmras::monitoring::Plugin *plugin = ibmras::monitoring::Plugin::processLibrary(dir + PATHSEPARATOR + LIBPREFIX + library + LIBSUFFIX);
	if (plugin) {
		IBMRAS_LOG_2(fine, "%s, version %s", (plugin->name).c_str(), (plugin->getVersion()));
		plugins.push_back(plugin);
	}
}

void Agent::addPlugin(const char* completeLibraryPath) {
	ibmras::monitoring::Plugin *plugin = ibmras::monitoring::Plugin::processLibrary(std::string(completeLibraryPath));
	if (plugin) {
		IBMRAS_LOG_2(fine, "%s, version %s", (plugin->name).c_str(), (plugin->getVersion()));
		plugins.push_back(plugin);
	}
}


void Agent::addSystemPlugins() {
//	addPlugin(ibmras::common::LogManager::getPlugin());
	addPlugin(
			(ibmras::monitoring::Plugin*) new ibmras::monitoring::agent::SystemReceiver());
}

void Agent::addConnector(ibmras::monitoring::connector::Connector* con) {
	connectionManager.addConnector(con);
}
void Agent::removeConnector(ibmras::monitoring::connector::Connector* con) {
	connectionManager.removeConnector(con);
}

void Agent::registerZipFunction(void(*zipFunc)(const char*)) {
	zipFunction = zipFunc;
}

void Agent::zipHeadlessFiles(const char* dir) {
	if (zipFunction == NULL) {
		IBMRAS_LOG(warning, "Zip called for by headless plugin, but no zip function set on Agent.");
	} else {
		zipFunction(dir);
	}
}

void Agent::init() {
	IBMRAS_DEBUG(info, "Agent initialisation : start");
	aCF.agentPushData = pushDataWrapper;
	aCF.agentSendMessage = sendMessageWrapper;
	aCF.logMessage = logMessageWrapper;
	aCF.getProperty = getPropertyWrapper;

	std::string searchPath = getAgentProperty("plugin.path");
	IBMRAS_DEBUG_1(debug, "Plugin search path : %s", searchPath.c_str());
	if (searchPath.size() > 0) {
		std::vector<ibmras::monitoring::Plugin*> found =
				ibmras::monitoring::Plugin::scan(searchPath);
		plugins.insert(plugins.begin(), found.begin(), found.end());
	}

	addSystemPlugins();
	setProperty("agent.native.build.date", getBuildDate());

	std::string pluginProperties = properties.toString();

	IBMRAS_DEBUG_1(info, "%d plugins found", plugins.size());
	uint32 provID = 0;
	for (std::vector<ibmras::monitoring::Plugin*>::iterator i =
			plugins.begin(); i != plugins.end(); ++i, provID++) {
		IBMRAS_DEBUG_1(fine, "Library : %s", (*i)->name.c_str());
		if ((*i)->init) {
			(*i)->init(pluginProperties.c_str());
		}
		if ((*i)->type & ibmras::monitoring::plugin::data) {
			addPushSource(i, provID);
			addPullSource(i, provID);
		}
	}
	createBuckets();
	addConnector(&configConn);
	IBMRAS_DEBUG(finest, bucketList.toString().c_str());
}

std::string Agent::getConfig(const std::string& name) {
	return configConn.getConfig(name);
}

bool Agent::readOnly() {
	std::string readOnlyMode = getAgentProperty("readonly");
	if (!readOnlyMode.compare("on")) {
		return true;
	}
	return false;
}


void Agent::start() {
	int result = 0;
	IBMRAS_DEBUG(info, "Agent start : begin");

	/* Receivers first as they are added to connection manager */
	IBMRAS_DEBUG(info, "Agent start : receivers");
	startReceivers();

	/* Connectors must be started before the plugins start pushing data */
	IBMRAS_DEBUG(info, "Agent start : connectors");
	startConnectors();

	IBMRAS_DEBUG(info, "Agent start : data providers");
	startPlugins();

	running = true; /* if any of the thread creation below fails then running will be set to false and started threads will exit */

	ibmras::common::port::ThreadData* data =
			new ibmras::common::port::ThreadData(processPullSourceLoop, endPullSourceLoop);
	result = ibmras::common::port::createThread(data);
	if (result) {
		running = false;
	} else {
		activeThreadCount++;
		data = new ibmras::common::port::ThreadData(processPublishLoop);
		result = ibmras::common::port::createThread(data);
		if (result) {
			running = false;
		}
	}
	IBMRAS_DEBUG(info, "Agent start : finish");
}

void Agent::startPlugins() {
	for (std::vector<ibmras::monitoring::Plugin*>::iterator i =
			plugins.begin(); i != plugins.end(); ++i) {
		if ((*i)->start) {
			IBMRAS_DEBUG_1(info, "Invoking plugin start method %s",
					(*i)->name.c_str());
			(*i)->start();
		} else {
			IBMRAS_DEBUG_1(info, "Warning : no start method defined on %s",
					(*i)->name.c_str());
		}
	}
}
void Agent::stopPlugins() {
	for (std::vector<ibmras::monitoring::Plugin*>::iterator i =
			plugins.begin(); i != plugins.end(); ++i) {
		if ((*i)->stop) {
			IBMRAS_DEBUG_1(info, "Invoking plugin stop method %s",
					(*i)->name.c_str());
			(*i)->stop();
		} else {
			IBMRAS_DEBUG_1(info, "Warning : no stop method defined on %s",
					(*i)->name.c_str());
		}
	}
}

BucketList* Agent::getBucketList() {
	return &bucketList;
}


void Agent::startReceivers() {
	for (std::vector<ibmras::monitoring::Plugin*>::iterator i =
			plugins.begin(); i != plugins.end(); ++i) {
		if ((*i)->type & ibmras::monitoring::plugin::receiver) {
			if ((*i)->recvfactory) {
				void* instance = (*i)->recvfactory();
				ibmras::monitoring::connector::Receiver* receiver =
						reinterpret_cast<ibmras::monitoring::connector::Receiver*>(instance);
				if (receiver) {
					IBMRAS_DEBUG_1(info, "Add receiver %s to connector manager",
							(*i)->name.c_str());
					connectionManager.addReceiver(receiver);
				}
			} else if ((*i)->receiveMessage) {
				ibmras::monitoring::connector::Receiver* receiver = 
						new ibmras::monitoring::AgentExtensionReceiver((*i)->receiveMessage);
				if (receiver) {
					IBMRAS_DEBUG_1(info, "Add extension receiver %s to connector manager",
							(*i)->name.c_str());
					connectionManager.addReceiver(receiver);
				}
			}
		}
	}
}

void Agent::startConnectors() {
	std::string connectorProperties = properties.toString();
	for (std::vector<ibmras::monitoring::Plugin*>::iterator i =
			plugins.begin(); i != plugins.end(); ++i) {
		IBMRAS_DEBUG_2(info, "Agent::startConnectors %s type is %d", (*i)->name.c_str(),
				(*i)->type);
		if ((*i)->type & ibmras::monitoring::plugin::connector) {
			IBMRAS_DEBUG(info, "it is a connector");
			if ((*i)->confactory) {
				IBMRAS_DEBUG_1(info, "Invoking factory method for %s",
						(*i)->name.c_str());
				void* instance = (*i)->confactory(connectorProperties.c_str());
				ibmras::monitoring::connector::Connector* con =
						reinterpret_cast<ibmras::monitoring::connector::Connector*>(instance);
				if (con) {
					IBMRAS_DEBUG(info, "Add connector to connector manager");
					connectionManager.addConnector(con);
					// Register the receiver with each connector
					con->registerReceiver(&connectionManager);
				}
			} else {
				IBMRAS_DEBUG_1(info, "Warning : no factory method defined on %s",
						(*i)->name.c_str());
			};
		}
	}
	connectionManager.start();
}

void Agent::stop() {
  // must wait for all threads to be started before we stop them (start is asynchronous)
	if(running && !startupLock.acquire()) {
		IBMRAS_DEBUG(info, "Agent stop : begin");
		running = false;
		connectionManager.stop();

		IBMRAS_DEBUG(fine, "Waiting for active threads to stop");
#if defined(_WINDOWS) || defined(_ZOS)
		while (activeThreadCount) {
			ibmras::common::port::sleep(1);
			IBMRAS_DEBUG_1(debug, "Checking thread count - current [%d]",
					activeThreadCount);
		}
#else
		ibmras::common::port::stopAllThreads();
#endif


		IBMRAS_DEBUG(fine, "All active threads now quit");

		stopPlugins();
		connectionManager.removeAllReceivers();
		connectionManager.removeAllConnectors();

		IBMRAS_DEBUG(info, "Agent stop : finish");
    startupLock.release();
	}
}

void Agent::shutdown() {

	IBMRAS_DEBUG(info, "Agent shutdown : begin");
	std::string str = bucketList.toString();
	IBMRAS_DEBUG(info, str.c_str());
	IBMRAS_DEBUG(info, "Agent shutdown : finish");
}

ibmras::monitoring::connector::Connector* Agent::getConnector(
		const std::string &id) {
	return connectionManager.getConnector(id);
}

ibmras::monitoring::connector::ConnectorManager* Agent::getConnectionManager() {
	return &connectionManager;
}


Agent* Agent::getInstance() {
	return instance;
}

bool Agent::addData(monitordata* data) {
	return bucketList.addData(data);
}

void Agent::threadStop() {
	activeThreadCount--;
	IBMRAS_DEBUG_1(debug, "Number of active threads %d", activeThreadCount);
}


void Agent::setProperties(const ibmras::common::Properties& props) {
	properties.add(props);
}

ibmras::common::Properties Agent::getProperties() {
	return properties;
}

void Agent::setProperty(const std::string& prop, const std::string& value) {
	properties.put(prop, value);
}



std::string Agent::getProperty(const std::string& prop) {
	return properties.get(prop);
}


bool Agent::propertyExists(const std::string& prop) {
	return properties.exists(prop);
}

std::string Agent::getAgentPropertyPrefix() {
	return PROPERTIES_PREFIX;
}

std::string Agent::getAgentProperty(const std::string& agentProp) {
	return getProperty(getAgentPropertyPrefix() + agentProp);
}

void Agent::setAgentProperty(const std::string& agentProp, const std::string& value) {
	setProperty(getAgentPropertyPrefix() + agentProp, value);
}

bool Agent::agentPropertyExists(const std::string& agentProp) {
	return propertyExists(getAgentPropertyPrefix() + agentProp);
}

bool Agent::isHeadlessRunning(){
	return headlessRunning;
}

void Agent::setHeadlessRunning(bool isRunning){
	headlessRunning = isRunning;

	// if we are in proper headless mode, then we need to toggle on/off
	// whether the agent is running to allow late attach to query this property
	std::string dataCollectionLevel = getAgentProperty("data.collection.level");
	if (ibmras::common::util::equalsIgnoreCase(dataCollectionLevel,"headless")) {
		if(headlessRunning) {
			setProperty("com.ibm.java.diagnostics.healthcenter.running", "true");
		} else {
			setProperty("com.ibm.java.diagnostics.healthcenter.running", "false");
		}
	}
}

bool Agent::loadPropertiesFile(const char* filestr){
	std::string filename(filestr);
	ibmras::common::PropertiesFile props;
	if (!props.load(filename)) {
		setProperties(props);
		return true;
	} else {
		return false;
	}
}


}
}
} /* end namespace monitoring */

