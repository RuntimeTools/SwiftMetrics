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
 * CpuPlugin.h
 *
 *  Created on: 30 Apr 2015
 *      Author: Admin
 */

#ifndef CPUPLUGIN_H_
#define CPUPLUGIN_H_

#include "AgentExtensions.h"
#include "../../agentcore/ibmras/monitoring/Typesdef.h"
#include <string>

namespace ibmras {
namespace monitoring {
namespace plugins {
namespace common {
namespace cpuplugin {

struct CPUTime {
	uint64 time; /* ns since fixed point */
	uint64 total; /* cumulative total cpu time in ns */
	uint64 process; /* cumulative process cpu time in ns */
	uint32 nprocs;
};

class CpuPlugin {
public:
	static agentCoreFunctions aCF;

	monitordata* OnRequestData();
	void OnComplete(monitordata* data);
	static pullsource* createSource(agentCoreFunctions aCF, uint32 provID);
	static CpuPlugin* getInstance();
	virtual ~CpuPlugin();
	int start();
	int stop();

private:
	uint32 provID;
	static CpuPlugin* instance;
	bool noFailures;
	struct CPUTime* last;
	struct CPUTime* current;

	CpuPlugin(uint32 provID);
	static char* NewCString(const std::string& s);
	static double clamp(double value, double min, double max);
	static double CalculateTotalCPU(struct CPUTime* start, struct CPUTime* finish);
	static double CalculateProcessCPU(struct CPUTime* start, struct CPUTime* finish);
	static void AppendCPUTime(std::stringstream& contentss);
	static bool IsValidData(struct CPUTime* cputime);
	static bool TimesAreDifferent(struct CPUTime* start, struct CPUTime* finish);
	pullsource* createPullSource(uint32 srcid, const char* name);
	CPUTime* getCPUTime();
#if defined(_WINDOWS)
	static bool read_total_cpu_time(uint64* unixtimestamp, uint64* totaltime);
#else
	static bool read_total_cpu_time(uint64* totaltime, const uint32 NS_PER_HZ);
#endif
	static bool read_process_cpu_time(uint64* proctime, const uint32 NS_PER_HZ);
#if defined(_AIX) || defined(__linux__) || defined(__MACH__) || defined(__APPLE__)
	static uint64 time_microseconds();
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






#endif /* CPUPLUGIN_H_ */
