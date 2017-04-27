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
 * MemoryPlugin.h
 *
 *  Created on: 5 May 2015
 *      Author: Admin
 */

#include "AgentExtensions.h"
#include "../../agentcore/ibmras/monitoring/Typesdef.h"
#include <string>

namespace ibmras {
namespace monitoring {
namespace plugins {
namespace common {
namespace memoryplugin {

class MemoryPlugin {
public:
	static agentCoreFunctions aCF;

	monitordata* OnRequestData();
	void OnComplete(monitordata* data);
	static pullsource* createSource(agentCoreFunctions aCF, uint32 provID);
	static MemoryPlugin* getInstance();
	virtual ~MemoryPlugin();
	int start();
	int stop();
private:
	uint32 provID;
	static MemoryPlugin* instance;
	bool noFailures;

	MemoryPlugin(uint32 provID);
	static int64 getProcessPhysicalMemorySize();
	static int64 getProcessPrivateMemorySize();
	static int64 getProcessVirtualMemorySize();
	static int64 getFreePhysicalMemorySize();
	static int64 getTotalPhysicalMemorySize();
	pullsource* createPullSource(uint32 srcid, const char* name);

	static char* NewCString(const std::string& s);
	int64 getTime();

};

typedef long		IDATA;
typedef size_t		UDATA;
#if defined(__linux__)
static IDATA openProcFile(const char *fname);
static IDATA readProcFile(const char *fname, char *buf, UDATA nbytes);
static char* getProcessName(char *name, UDATA nameLength);
static const char* skipFields(const char *str, UDATA n);
static IDATA readProcStatField(UDATA index, const char *format, ...);
#endif

#if defined(__MACH__) || defined(__APPLE__)

#endif

monitordata* pullWrapper();
void pullCompleteWrapper(monitordata* data);

extern "C" {
PLUGIN_API_DECL pullsource* ibmras_monitoring_registerPullSource(agentCoreFunctions aCF, uint32 provID);
PLUGIN_API_DECL int ibmras_monitoring_plugin_init(const char* properties);
PLUGIN_API_DECL int ibmras_monitoring_plugin_start();
PLUGIN_API_DECL int ibmras_monitoring_plugin_stop();
PLUGIN_API_DECL const char* ibmras_monitoring_getVersion();
}

const std::string COMMA = ",";
const std::string EQUALS = "=";

const std::string MEMORY_SOURCE = "MemorySource";
const std::string TOTAL_MEMORY = "totalphysicalmemory";
const std::string PHYSICAL_MEMORY = "physicalmemory";
const std::string PRIVATE_MEMORY = "privatememory";
const std::string VIRTUAL_MEMORY = "virtualmemory";
const std::string FREE_PHYSICAL_MEMORY = "freephysicalmemory";
const std::string TOTAL_PHYSICAL_MEMORY = "totalphysicalmemory";

} //memoryplugin
} //common
} //plugins
} //monitoring
} //ibmras
