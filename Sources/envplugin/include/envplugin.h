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
 * envplugin.h
 *
 *  Created on: 21 Apr 2015
 *      Author: MC
 */

#ifndef ibmras_monitoring_plugins_common_environment_envplugin_h
#define ibmras_monitoring_plugins_common_environment_envplugin_h

#include "AgentExtensions.h"
#include "../../agentcore/ibmras/monitoring/Typesdef.h"
#include <string>

namespace ibmras {
namespace monitoring {
namespace plugins {
namespace common {
namespace environment {

class EnvPlugin {
public:
	static agentCoreFunctions aCF;

    std::string arch; 
	std::string osName;
	std::string osVersion;
	std::string nprocs;
	std::string pid;
	std::string commandLine;
	std::string agentVersion;
	std::string agentNativeBuildDate;

	monitordata* OnRequestData();
	void OnComplete(monitordata* data);
	static pullsource* createSource(agentCoreFunctions aCF, uint32 provID);
	static EnvPlugin* getInstance();
	virtual ~EnvPlugin();
	int start();
	int stop();

private:
	uint32 provID;
	static EnvPlugin* instance;

	EnvPlugin(uint32 provID);
	static char* NewCString(const std::string& s);
    void AppendEnvVars(std::stringstream &ss);
    void AppendSystemInfo(std::stringstream &ss);
	pullsource* createPullSource(uint32 srcid, const char* name);
    static void initStaticInfo();
#if defined(_WINDOWS)
    static const std::string GetWindowsMajorVersion();
    static const std::string GetWindowsBuild();
#else
    static std::string GetCommandLine();
#endif

};
/*-------------------------------------------------------------------------------------
 * These are the namespace functions that are used to avoid the restrictions imposed
 * by the defined typedefs for callback functions. Non-static member function pointers
 * would have a different prototype than the one generically typedef'd in the headers,
 * which is:
 * typedef monitordata* (*PULL_CALLBACK)(void);
 * typedef void (*PULL_CALLBACK_COMPLETE)(monitordata*);
 * These functions will be passed to the agent using the pullsource* structure that is
 * returned by the registerPullSource method.
 *-----------------------------------------------------------------------------------*/
monitordata* pullWrapper();
void pullCompleteWrapper(monitordata* data);
#if defined(__MACH__) || defined(__APPLE__)
std::string getCommandOutput(std::string command);
#endif
/*
 * These 4 functions are the symbols that the Plugin.scan method will look for when scanning the
 * plugins directory, therefore they must be declared as extern "C" so their names are not mangled
 * by the compiler. Also, PLUGIN_API_DECL must be in front of the declarations so the f's are exported
 * when a Windows dll is generated.
 */
extern "C" {
PLUGIN_API_DECL pullsource* ibmras_monitoring_registerPullSource(agentCoreFunctions aCF, uint32 provID);
PLUGIN_API_DECL int ibmras_monitoring_plugin_init(const char* properties);
PLUGIN_API_DECL int ibmras_monitoring_plugin_start();
PLUGIN_API_DECL int ibmras_monitoring_plugin_stop();
PLUGIN_API_DECL const char* ibmras_monitoring_getVersion();
}

}
}
}
}
}

//#endif
#endif /* ENVIRONMENTPLUGIN_H_ */
