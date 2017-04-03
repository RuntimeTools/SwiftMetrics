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


#ifndef ibmras_monitoring_plugin_h
#define ibmras_monitoring_plugin_h

#include "AgentExtensions.h"
#include "Typesdef.h"
#include <vector>
#include <string>

#include "../common/util/LibraryUtils.h"

typedef void* (*RECEIVER_FACTORY)();	/* short cut for the function pointer for the factory used to create a Receiver object for the plugin */

namespace ibmras {
namespace monitoring {

namespace plugin {

enum PluginType {none = 0, data = 1, connector = 2, receiver = 4};

} /* end namespace Plugin */


/*
 * Defines a plugin that implements either push and/or pull source functions
 */
class Plugin {
public:
	Plugin();
	virtual ~Plugin() {}

	void unload();

	static std::vector<Plugin*> scan(const std::string &dir); /* scan a directory and return a list of candidate plugins */
	static Plugin* processLibrary(const std::string &filePath);

	std::string name;										/* name of the library - typically this is the full path */
	const char* version;

	int (*init)(const char *properties);				/* Plugin inialization method */
	pushsource* (*push)(agentCoreFunctions, uint32);	/* push source function pointer or NULL */
	pullsource* (*pull)(agentCoreFunctions, uint32);							/* pull source function pointer or NULL */
	int (*start)(void);									/* start function to begin data production */
	int (*stop)(void);										/* stop function to end data production */
	const char* (*getVersion)(void);								/* returns plugin version, used to enforce versioning */
	CONNECTOR_FACTORY confactory;							/* Connector factory */
	RECEIVER_FACTORY recvfactory;                           /* Receiver factory */
	RECEIVE_MESSAGE receiveMessage;							/* receiveMessage function to be wrapped by an AgentExtensionReceiver */
	ibmras::common::util::LibraryUtils::Handle handle;	/* handle to be used when closing the dynamically loaded plugin */
	int type;

private:
	void setType();
};



}
}

#endif /* ibmras_monitoring_plugin_h */
