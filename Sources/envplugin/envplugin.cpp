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
#define _XOPEN_SOURCE_EXTENDED 1 //This macro makes zOS' unistd.h expose gethostname().
#endif


#include "envplugin.h"
#include "AgentExtensions.h"
#include "../agentcore/ibmras/monitoring/Typesdef.h"
#include <iostream>
#include <cstring>
#include <sstream>
#include <fstream>
#include <cstdlib>

#if defined(__linux__)
#include <sys/utsname.h> // uname()
#include <sys/sysinfo.h> // get_nprocs()
#include <unistd.h> // gethostname()
#endif

#if defined(__MACH__) || defined(__APPLE__)
#include <sys/types.h>
#include <sys/sysctl.h>
#include <mach/machine.h>
#include <errno.h>
#include <sys/user.h>
#include <sys/proc.h>
#include <stdlib.h>
#include <stdio.h>
#include <libproc.h>
#include <unistd.h> // gethostname()
#define HOST_NAME_MAX 256
#endif

#if defined(_AIX)
#include_next </usr/include/sys/systemcfg.h>
#include <sys/utsname.h> // uname()
#include <sys/sysinfo.h> // get_nprocs()
#include <unistd.h> // gethostname()
#include <procinfo.h>
#include <sys/types.h>
#endif

#ifdef _WINDOWS
#include "windows.h"
#define HOST_NAME_MAX 256
#endif
#ifdef _ZOS
#define HOST_NAME_MAX 256
#endif

#define ENVIRONMENT_PULL_INTERVAL 1200

namespace ibmras {
namespace monitoring {
namespace plugins {
namespace common {
namespace environment {


#if defined(__linux__) || defined(_AIX) || defined(_ZOS) || defined(__MACH__) || defined(__APPLE__)
extern "C" char **environ; // use GetEnvironmentStrings() on Windows (maybe getenv() on POSIX?)
#endif


template <class T>
std::string itoa(T t);

#define DEFAULT_BUCKET_CAPACITY 1024*10

EnvPlugin* EnvPlugin::instance = NULL;
agentCoreFunctions EnvPlugin::aCF;

	EnvPlugin::EnvPlugin(uint32 provID): 
		provID(provID) {
	}
	
	EnvPlugin::~EnvPlugin(){}

	
	int EnvPlugin::start() {
		aCF.logMessage(debug, ">>>EnvPlugin::start()");
		EnvPlugin::initStaticInfo(); // See below for platform-specific implementation, protected by ifdefs
		aCF.logMessage(debug, "<<<EnvPlugin::start()");
		return 0;
	}

	int EnvPlugin::stop() {
			aCF.logMessage(debug, ">>>EnvPlugin::stop()");
			aCF.logMessage(debug, "<<<EnvPlugin::stop()");
			return 0;
	}

	pullsource* EnvPlugin::createSource(agentCoreFunctions aCF, uint32 provID) {
		aCF.logMessage(fine, "[env_os] Registering pull source");
		if(!instance) {
			EnvPlugin::aCF = aCF;
			instance = new EnvPlugin(provID);
		}
		return instance->createPullSource(0, "common_env");
	}

	EnvPlugin* EnvPlugin::getInstance() {
		return instance;
	}

	char* EnvPlugin::NewCString(const std::string& s) {
		char *result = new char[s.length() + 1];
		std::strcpy(result, s.c_str());
		return result;
	}

void EnvPlugin::AppendEnvVars(std::stringstream &ss) {
	bool hostnameDefined = false;
	int i = 0;
	while (environ[i] != NULL) {
		ss << "environment." << environ[i] << '\n';
		if (std::strncmp("HOSTNAME=", environ[i], std::strlen("HOSTNAME=")) == 0) {
			hostnameDefined = true;
		}
		i++;
	}
	if (!hostnameDefined) {
		char hostname[HOST_NAME_MAX + 1];
		if (gethostname(hostname, HOST_NAME_MAX) == 0) {
			ss  << "environment.HOSTNAME=" << hostname << '\n'; 
		}
	}
}

void EnvPlugin::AppendSystemInfo(std::stringstream &ss) {
	ss << "os.arch="     << EnvPlugin::getInstance()->arch             << '\n'; // eg "amd64"
	ss << "os.name="     << EnvPlugin::getInstance()->osName           << '\n'; // eg "Windows 7"
	ss << "os.version="  << EnvPlugin::getInstance()->osVersion        << '\n'; // eg "6.1 build 7601 Service Pack 1"
	ss << "pid="         << EnvPlugin::getInstance()->pid              << '\n'; // eg "12345"
	ss << "native.library.date=" << EnvPlugin::getInstance()->agentNativeBuildDate << '\n'; // eg "Oct 10 2014 11:44:56"
	ss << "jar.version=" << EnvPlugin::getInstance()->agentVersion     << '\n'; // eg "3.0.0.20141030"
	ss << "number.of.processors=" << EnvPlugin::getInstance()->nprocs  << '\n'; // eg 8
	ss << "command.line=" << EnvPlugin::getInstance()->commandLine     << '\n';
}

monitordata* EnvPlugin::OnRequestData() {
	aCF.logMessage(debug, ">>>EnvPlugin::OnRequestData");
	monitordata *data = new monitordata;
	data->provID = provID;
	data->sourceID = 0;
	
	std::stringstream contentss;
	contentss << "#EnvironmentSource\n";
	AppendEnvVars(contentss);
	AppendSystemInfo(contentss);
	
	std::string content = contentss.str();
	data->size = static_cast<uint32>(content.length()); // should data->size be a size_t?
	data->data = NewCString(content);
	data->persistent = false;
	aCF.logMessage(debug, "<<<EnvPlugin::OnRequestData");
	return data;
}

void EnvPlugin::OnComplete(monitordata* data) {
	if (data != NULL) {
		if (data->data != NULL) {
			delete[] data->data;
		}
		delete data;
	}
}

pullsource* EnvPlugin::createPullSource(uint32 srcid, const char* name) {
	pullsource *src = new pullsource();
	src->header.name = name;
	std::string desc("Description for ");
	desc.append(name);
	src->header.description = NewCString(desc);
	src->header.sourceID = srcid;
	src->next = NULL;
	src->header.capacity = DEFAULT_BUCKET_CAPACITY;
	src->callback = pullWrapper;
	src->complete = pullCompleteWrapper;
	src->pullInterval = ENVIRONMENT_PULL_INTERVAL;
	return src;
}

	/*****************************************************************************
	 * CALLBACK WRAPPERS
	 *****************************************************************************/

	monitordata* pullWrapper() {
		return EnvPlugin::getInstance()->OnRequestData();
	}

	void pullCompleteWrapper(monitordata* data) {
		EnvPlugin::getInstance()->OnComplete(data);
	}

	/*****************************************************************************
	 * FUNCTIONS EXPORTED BY THE LIBRARY
	 *****************************************************************************/

extern "C" {
	pullsource* ibmras_monitoring_registerPullSource(agentCoreFunctions aCF, uint32 provID) {
		aCF.logMessage(fine, ">>>ibmras_monitoring_registerPullSource");
		pullsource *source = EnvPlugin::createSource(aCF, provID);
		EnvPlugin::getInstance()->agentVersion = std::string(aCF.getProperty("agent.version"));
		EnvPlugin::getInstance()->agentNativeBuildDate = std::string(aCF.getProperty("agent.native.build.date"));
		aCF.logMessage(fine, "<<<ibmras_monitoring_registerPullSource");
		return source;
	}

	int ibmras_monitoring_plugin_init(const char* properties) {
		return 0;
	}

	int ibmras_monitoring_plugin_start() {
		EnvPlugin::aCF.logMessage(fine, "[environment_os] Starting");
		return EnvPlugin::getInstance()->start();
	}

	int ibmras_monitoring_plugin_stop() {
		EnvPlugin::aCF.logMessage(fine, "[environment_os] Stopping");
		return EnvPlugin::getInstance()->stop();
	}

	const char* ibmras_monitoring_getVersion() {
	return PLUGIN_API_VERSION;
	}
}

/* 
 * Linux
 */
#if defined(__linux__)
std::string EnvPlugin::GetCommandLine() {
	std::stringstream filenamess;
	filenamess << "/proc/" << getpid() << "/cmdline";
	std::string filename = filenamess.str();
	
	std::ifstream filestream(filename.c_str());

	if (!filestream.is_open()) {

		std::stringstream envss;
		envss << "Failed to open " << filename.c_str();

		return "";
	}

    std::istreambuf_iterator<char> begin(filestream), end;
    std::string cmdline(begin, end);
    filestream.close();
	
	for (unsigned i=0; i < cmdline.length(); i++) {
		if (cmdline[i] == '\0') {
			cmdline[i] = ' ';
		}
	}
	return cmdline;	
}

void EnvPlugin::initStaticInfo() {
	struct utsname sysinfo;
	int rc = uname(&sysinfo);
	if (rc >= 0) {
		EnvPlugin::getInstance()->arch = std::string(sysinfo.machine);
		EnvPlugin::getInstance()->osName = std::string(sysinfo.sysname);
		EnvPlugin::getInstance()->osVersion = std::string(sysinfo.release) + std::string(sysinfo.version);
	} else {
		EnvPlugin::getInstance()->arch = "unknown"; // could fallback to compile-time information
		EnvPlugin::getInstance()->osName = "Linux";
		EnvPlugin::getInstance()->osVersion = "";
	}

	EnvPlugin::getInstance()->nprocs = itoa(get_nprocs());
	EnvPlugin::getInstance()->pid = itoa(getpid());
	EnvPlugin::getInstance()->commandLine = GetCommandLine();
}

#endif

/* 
 * AIX 
 */
#if defined (_AIX)

std::string EnvPlugin::GetCommandLine() {
	struct procsinfo proc;
	char procargs[512]; // Is this a decent length? Should we heap allocate and expand?
	
	proc.pi_pid = getpid();
	int rc = getargs(&proc, sizeof(proc), procargs, sizeof(procargs));
	if (rc < 0) {



		std::stringstream envss;
		envss << "Failed to get command line " << errno;
		aCF.logMessage(debug, envss.str().c_str());

		return std::string();
	}
	std::stringstream cmdliness;
	char *current = procargs;
	int written = 0;
	while (std::strlen(current) > 0) {
		if (written++ > 0) cmdliness << ' ';
		cmdliness << current;
		current = current + std::strlen(current) + 1;
	}
	return cmdliness.str();
}

void EnvPlugin::initStaticInfo() {
	struct utsname sysinfo;
	int rc = uname(&sysinfo);
	if (rc >= 0) {
		uint64_t architecture = getsystemcfg(SC_ARCH);
		uint64_t width = getsystemcfg(SC_WIDTH);
		
		std::string bits = (width == 32) ? "32" : 
		                   (width == 64) ? "64" : 
		                   "";
		EnvPlugin::getInstance()->arch = (architecture == POWER_PC) ? "ppc" : "";
		if (EnvPlugin::getInstance()->arch != "") {
			EnvPlugin::getInstance()->arch += bits;
		} else {
			EnvPlugin::getInstance()->arch = std::string(sysinfo.machine);
		}
		EnvPlugin::getInstance()->osName = std::string(sysinfo.sysname);
		EnvPlugin::getInstance()->osVersion = std::string(sysinfo.release) + std::string(sysinfo.version);
	} else {
		EnvPlugin::getInstance()->arch = "unknown"; // could fallback to compile-time information
		EnvPlugin::getInstance()->osName = "AIX";
		EnvPlugin::getInstance()->osVersion = "";
	}
	// might be _SC_NPROCESSORS_ONLN -https://www.ibm.com/developerworks/community/forums/html/topic?id=77777777-0000-0000-0000-000014250083
	EnvPlugin::getInstance()->nprocs = itoa(sysconf(_SC_NPROCESSORS_CONF));
	EnvPlugin::getInstance()->pid = itoa(getpid());
	EnvPlugin::getInstance()->commandLine = GetCommandLine();
}

#endif


#if defined(__APPLE__) || defined(__MACH__)

std::string EnvPlugin::GetCommandLine() {

	int pid = getpid();

	char buf[128];
	proc_name(pid, buf, 128);

	std::string app = std::string(buf);

	/*
	 * Second part of this workaround, is to execute ps -f and then parse it to only get
	 * the command and arguments passed to it, (with the help of the fact that we know
	 * the name of the executable from the above search)
	 */

	std::stringstream command;
	command <<"ps -f"<<pid;
	std::string commandOutput = getCommandOutput(command.str());
	int argsPos = commandOutput.find(app);
	std::string argv;

	if(argsPos != std::string::npos) {
		argv = commandOutput.substr(argsPos);
	} else {

		std::stringstream errorss;
		errorss << "[env_os] Exec not found in ps -f output";
		aCF.logMessage(warning, errorss.str().c_str());
		return "";
	}

	  return argv;
}

void EnvPlugin::initStaticInfo() {

	//Machine's architecture
	int mib[2] = {CTL_HW, HW_MACHINE};
	char architecture[64];
	size_t len = sizeof(architecture);
	int res = sysctl(mib, 2, architecture, &len, NULL, 0);
	if(!res){
		EnvPlugin::getInstance()->arch = std::string(architecture);
	} else {
		EnvPlugin::getInstance()->arch = "";

		std::stringstream errorss;
		errorss << "[env_os] CPU arch not set, error: ";
		errorss << strerror(errno);
		aCF.logMessage(warning, errorss.str().c_str());
	}

	//Amount of physical CPUs
	int phys = 0;
	len = sizeof(phys);
	res = sysctlbyname("hw.physicalcpu", &phys, &len, NULL, 0);
	if(!res){
		EnvPlugin::getInstance()->nprocs = itoa(phys);
	} else {
		EnvPlugin::getInstance()->nprocs = "";

		std::stringstream errorss;
		errorss << "[env_os] Number of CPUs not set, error: ";
		errorss << strerror(errno);
		aCF.logMessage(warning, errorss.str().c_str());
	}

	//Process ID
	int pid = getpid();
	EnvPlugin::getInstance()->pid = itoa(pid);

	//Command line
	EnvPlugin::getInstance()->commandLine = GetCommandLine();

	//OS version and name
	std::string osVersion;
	osVersion = getCommandOutput("sw_vers -productVersion");
	EnvPlugin::getInstance()->osVersion = osVersion.substr(0, osVersion.find("\n"));

	std::string osType;
	osType = getCommandOutput("sw_vers -productName");
	EnvPlugin::getInstance()->osName = osType.substr(0, osType.find("\n"));

}

std::string getCommandOutput(std::string command) {
	FILE *fp;
	char str[40];
	std::stringstream output;
	fp = popen(command.c_str(), "r");
	while (fgets(str, sizeof(str), fp))
	{
	  output << str;
	}
	pclose(fp);
	return output.str().c_str();
}

#endif

/*
 * Windows
 */
#ifdef _WINDOWS
const std::string EnvPlugin::GetWindowsMajorVersion() {
	OSVERSIONINFOEX versionInfo;
	versionInfo.dwOSVersionInfoSize = sizeof(versionInfo);
	
	static const std::string defaultVersion = "Windows";
	
	if (!GetVersionEx((OSVERSIONINFO *) &versionInfo)) {
		return defaultVersion;
	}
	
	switch (versionInfo.dwPlatformId) {
	case VER_PLATFORM_WIN32s: return "Windows 3.1";
	case VER_PLATFORM_WIN32_WINDOWS:
		switch (versionInfo.dwMinorVersion) {
		case 0: return "Windows 95";
		case 90: return "Windows Me";
		default: return "Windows 98";
		}
		break; /* VER_PLATFORM_WIN32_WINDOWS */
		
	case VER_PLATFORM_WIN32_NT:
		if (versionInfo.dwMajorVersion < 5)  {
			return "Windows NT";
			
		} else if (versionInfo.dwMajorVersion == 5) {
			switch (versionInfo.dwMinorVersion) {
			case 0: return "Windows 2000";
			/* case 1: WinNT 5.1 => Windows XP. Handled by the default. */
			case 2:
				/* WinNT 5.2 can be either Win2003 Server or Workstation (e.g. XP64).
				 * Report workstation products as "Windows XP".
				 * See CMVC 89090 and CMVC 89127 */
				switch (versionInfo.wProductType) {
				case VER_NT_WORKSTATION: return "Windows XP";
				case VER_NT_DOMAIN_CONTROLLER:
				case VER_NT_SERVER:
				default: return "Windows Server 2003";
				}
			default: return "Windows XP";
			}
			
		} else if (versionInfo.dwMajorVersion == 6) {
			switch (versionInfo.wProductType) {
			case VER_NT_WORKSTATION:
				switch (versionInfo.dwMinorVersion) {
				case 0: return "Windows Vista";
				case 1: return "Windows 7";
				case 2: return "Windows 8";
				default: return defaultVersion;
				} /* VER_NT_WORKSTATION */
			default:
				switch (versionInfo.dwMinorVersion) {
				case 0: return "Windows Server 2008";
				case 1: return "Windows Server 2008 R2";
				case 2: return "Windows Server 2012";
				default: return defaultVersion;
				}
			}
		} else {
			return defaultVersion;
		}
		break; /* VER_PLATFORM_WIN32_NT */
			
	default: return defaultVersion;
	}
}

const std::string EnvPlugin::GetWindowsBuild() {
	OSVERSIONINFOW versionInfo;
	int len = sizeof("0123456789.0123456789 build 0123456789 ") + 1;
	char *buffer;
	int position;
	
	static const std::string defaultBuild = "";
	
	versionInfo.dwOSVersionInfoSize = sizeof(OSVERSIONINFOW);
	
	if (!GetVersionExW(&versionInfo)) {
		return defaultBuild;
	}

	if (NULL != versionInfo.szCSDVersion) {
		len += WideCharToMultiByte(CP_UTF8, 0, versionInfo.szCSDVersion, -1, NULL, 0, NULL, NULL);
	}
	buffer = new char[len];
	if (NULL == buffer) {
		return defaultBuild;
	}
	position = sprintf(buffer,"%d.%d build %d",
		versionInfo.dwMajorVersion,
		versionInfo.dwMinorVersion,
		versionInfo.dwBuildNumber & 0x0000FFFF);

	if ((NULL != versionInfo.szCSDVersion) && ('\0' != versionInfo.szCSDVersion[0])) {
		buffer[position++] = ' ';
		WideCharToMultiByte(CP_UTF8, 0, versionInfo.szCSDVersion, -1, &buffer[position], len - position - 1, NULL, NULL);
	}
	
	std::string version(buffer);
	delete[] buffer;
	return version;
}

void EnvPlugin::initStaticInfo() {
	SYSTEM_INFO sysinfo;
	GetSystemInfo(&sysinfo);
	switch (sysinfo.wProcessorArchitecture) {
	case PROCESSOR_ARCHITECTURE_AMD64: EnvPlugin::getInstance()->arch = "x86_64"; break;
	case PROCESSOR_ARCHITECTURE_ARM: EnvPlugin::getInstance()->arch = "arm"; break;
	case PROCESSOR_ARCHITECTURE_IA64: EnvPlugin::getInstance()->arch = "itanium"; break;
	case PROCESSOR_ARCHITECTURE_INTEL: EnvPlugin::getInstance()->arch = "x86"; break;
	default: 
		EnvPlugin::getInstance()->arch = "unknown"; // could fallback to compile-time information
		break;
	}
	EnvPlugin::getInstance()->osName = GetWindowsMajorVersion();
	EnvPlugin::getInstance()->osVersion = GetWindowsBuild();
	EnvPlugin::getInstance()->nprocs = itoa(sysinfo.dwNumberOfProcessors);
	EnvPlugin::getInstance()->pid = itoa(GetCurrentProcessId());
	EnvPlugin::getInstance()->commandLine = std::string(GetCommandLine());
}
#endif

template <class T>
std::string itoa(T t) {
	std::stringstream s;
	s << t;
	return s.str();
}

}//environment
}//common
}//plugins
}//monitoring
}//ibmras


