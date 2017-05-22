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


#ifndef ibmras_monitoring_agent_agent_h
#define ibmras_monitoring_agent_agent_h

#include "AgentExtensions.h"
#include "../Typesdef.h"
#include "DataSource.h"
#include "DataSourceList.h"
#include "../connector/Connector.h"
#include "BucketList.h"
#include "../connector/ConnectorManager.h"
#include "../Plugin.h"
#include "../../common/Logger.h"
#include "../../common/LogManager.h"
#include "../../common/Properties.h"
#include "../connector/configuration/ConfigurationConnector.h"

#include <string>
/*
 * Definitions for the internal workings of the agent
 *
 */

extern "C" {

void initWrapper();
void startWrapper();
void stopWrapper();
void shutdownWrapper();
void setLogLevelsWrapper();
const char* getVersionWrapper();
void logCoreMessageWrapper(loggingLevel lev, const char * message);
void setPropertyWrapper(const char* key, const char* value);
const char* getPropertyWrapper(const char* key);
bool loadPropertiesFileWrapper(const char* fileName);
void registerZipFunctionWrapper(void(*zF)(const char*));
void addPluginWrapper(const char*);

}

namespace ibmras {
namespace monitoring {
namespace agent {

void setPropertyImpl(const char* key, const char* value);
const char* getPropertyImpl(const char* key);

class DECL Agent{
public:
	static Agent* getInstance();			/* return the singleton instance of the agent */
	void init();							/* invoke to start the agent initialisation lifecycle event */
	void start();							/* invoke to start the agent start lifecycle event */
	void stop();							/* invoke to start the agent stop lifecycle event */
	void shutdown();						/* invoke to shutdown the agent, it cannot be restarted after this */
	bool loadPropertiesFile(const char* filename);
											/* the location of the healthcenter.properties file to load */

	static std::string getBuildDate();
	static std::string getVersion();

	void addConnector(ibmras::monitoring::connector::Connector* con);
	void removeConnector(ibmras::monitoring::connector::Connector* con);
	DataSourceList<pullsource> getPullSources();
	DataSourceList<pushsource> getPushSources();
	DataSource<pullsource>* getPullSource(std::string uniqueID);
	DataSource<pushsource>* getPushSource(std::string uniqueID);
	BucketList* getBucketList();

	ibmras::monitoring::connector::Connector* getConnector(const std::string &id);
	ibmras::monitoring::connector::ConnectorManager* getConnectionManager();
	bool addData(monitordata* data);

	void publish();							/* publish messages to connectors */
	void republish(const std::string &prefix); /* republish history */
	void immediateUpdate(); /* Signal immediate update from pullsources */

	void threadStop();						/* fired when an agent processing thread stops */
	void setLogOutput(ibmras::common::LOCAL_LOGGER_CALLBACK func);
	void setLogLevels();
	void setLocalLog(bool local);
	void addPlugin(ibmras::monitoring::Plugin* plugin);	/* manually add a plugin to the agent */
	void addPlugin(const std::string &dir, const std::string library);	/* manually add a plugin to the agent */
    void addPlugin(const char* completeLibraryPath);	/* manually add a plugin to the agent */

	ibmras::common::Properties getProperties();
	void setProperties(const ibmras::common::Properties &props);
	void setProperty(const std::string &prop, const std::string &value);
	std::string getProperty(const std::string &prop);
	bool propertyExists(const std::string &prop);
	std::string getAgentPropertyPrefix();
	std::string getAgentProperty(const std::string &agentProp);
	void setAgentProperty(const std::string &agentProp, const std::string &value);
	bool agentPropertyExists(const std::string &agentProp);
	
	bool isHeadlessRunning();
	void setHeadlessRunning(bool);
		
	std::string getConfig(const std::string& name);
	bool readOnly();
	void registerZipFunction(void(*zipFn)(const char*));
	void zipHeadlessFiles(const char* dir);
  ibmras::common::port::Lock startupLock;

	Agent();					/* public constructor */

private:
	void addPushSource(std::vector<ibmras::monitoring::Plugin*>::iterator i, uint32 provID);
	void addPullSource(std::vector<ibmras::monitoring::Plugin*>::iterator i, uint32 provID);
	void addSystemPlugins(); /* adds agent internal / system push or pull sources */
	void createBuckets();
	void startPlugins(); 		/* call the start method on each plugin */
	void stopPlugins(); 		/* call the stop method on each plugin */
	void startConnectors(); 		/* initialise the connectors */
	void startReceivers(); 		/* initialise any receivers */
	BucketList bucketList;

	ibmras::monitoring::connector::ConnectorManager connectionManager;
	DataSourceList<pushsource> pushSourceList;
	DataSourceList<pullsource> pullSourceList;
	std::vector<ibmras::monitoring::Plugin*> plugins;
	uint32 activeThreadCount;		/* number of active threads */
	//static Agent* instance;		/* singleton instance */
	ibmras::common::Properties properties;
	ibmras::monitoring::connector::ConfigurationConnector configConn;
	void(*zipFunction)(const char*);

};
}
}
} /* end namespace agent */


#endif /* ibmras_monitoring_agent_agent_h */
