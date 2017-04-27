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
 * MemoryPlugin.cpp
 *
 *  Created on: 5 May 2015
 *      Author: Admin
 */

#include "AgentExtensions.h"
#include "../agentcore/ibmras/monitoring/Typesdef.h"
#include "MemoryPlugin.h"
#include <cstring>
#include <string>
#include <sstream>
#include <ctime>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <iostream>

#if defined(__linux__)
#include <sys/param.h>
#include <sys/sysinfo.h>
#include <sys/time.h>
#include <unistd.h>
#include <stdarg.h>
#endif

#if defined(__MACH__) || defined(__APPLE__)
#include <sys/types.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <mach/mach.h>
#endif

#if defined(_WINDOWS)
#include <windows.h>
#include <pdh.h>
#include <pdhmsg.h>
#include <winbase.h>
#include <psapi.h>
#pragma comment(lib, "psapi.lib")
#endif

#if defined(AIXPPC)
#include <unistd.h>
#include <alloca.h>
#include <procinfo.h>
#include <sys/vminfo.h>
#include <sys/procfs.h>
#include <sys/resource.h>
#include <sys/types.h>

#if !defined(VMINFO_GETPSIZES)

#define VMINFO_GETPSIZES  102 /* report a system's supported page sizes */
#define VMINFO_PSIZE      103 /* report statistics for a page size */

struct vminfo_psize
{
	psize_t psize; /* IN: page size                        */

	/* The rest of this struct is output from vmgetinfo()           */

	uint64_t attr; /* bitmap of page size's attributes     */

	/* Page size attributes reported in the vminfo_psize.attr field: */
#define VM_PSIZE_ATTR_PAGEABLE       0x1  /* page size supports paging  */

	uint64_t pgexct; /* count of page faults                 */
	uint64_t pgrclm; /* count of page reclaims               */
	uint64_t lockexct; /* count of lockmisses                  */
	uint64_t backtrks; /* count of backtracks                  */
	uint64_t pageins; /* count of pages paged in              */
	uint64_t pageouts; /* count of pages paged out             */
	uint64_t pgspgins; /* count of page ins from paging space  */
	uint64_t pgspgouts; /* count of page outs from paging space */
	uint64_t numsios; /* count of start I/Os                  */
	uint64_t numiodone; /* count of iodones                     */
	uint64_t zerofills; /* count of zero filled pages           */
	uint64_t exfills; /* count of exec filled pages           */
	uint64_t scans; /* count of page scans by clock         */
	uint64_t cycles; /* count of clock hand cycles           */
	uint64_t pgsteals; /* count of page steals                 */
	uint64_t freewts; /* count of free frame waits            */
	uint64_t extendwts; /* count of extend XPT waits            */
	uint64_t pendiowts; /* count of pending I/O waits           */

	/*
	* the next fields need to be computed by vmgetinfo
	* system call, else their value will be inaccurate.
	*/
	rpn64_t numframes; /* # of real memory frames of this psize */
	rpn64_t numfrb; /* number of pages on free list */
	rpn64_t numclient; /* number of client frames */
	rpn64_t numcompress; /* no of frames in compressed segments */
	rpn64_t numperm; /* number frames non-working segments */
	rpn64_t numvpages; /* accessed virtual pages */
	rpn64_t minfree; /* minimun pages free list (fblru) */
	rpn64_t maxfree; /* maxfree pages free list (fblru) */
#ifndef RPTYPES
#define RPTYPES         2
#endif
	rpn64_t rpgcnt[RPTYPES];/* repaging cnt */
	rpn64_t numpout; /* number of fblru page-outs        */

	rpn64_t numremote; /* number of fblru remote page-outs */
	rpn64_t numwseguse; /* count of pages in use for working seg */
	rpn64_t numpseguse; /* count of pages in use for persistent seg */
	rpn64_t numclseguse; /* count of pages in use for client seg */
	rpn64_t numwsegpin; /* count of pages pinned for working seg */
	rpn64_t numpsegpin; /* count of pages pinned for persistent seg */
	rpn64_t numclsegpin; /* count of pages pinned for client seg */
	rpn64_t numpgsp_pgs; /* # of wseg pages with allocated paging space */

	rpn64_t numralloc; /* number of remote allocations */
	rpn64_t pfrsvdblks; /* number of system reserved blocks */
	rpn64_t pfavail; /* number of pages available for pinning */
	rpn64_t pfpinavail; /* app-level num pages avail for pinning */
	rpn64_t numpermio; /* number of fblru non-w.s. pageouts    */

	rpn64_t system_pgs; /* pages on SCBs marked V_SYSTEM        */
	rpn64_t nonsys_pgs; /* pages on SCBs not marked V_SYSTEM    */
};

#endif /* !defined(VMINFO_GETPSIZES) */
#endif

#define MEMSOURCE_PULL_INTERVAL 2
#define DEFAULT_CAPACITY 1024*10

namespace ibmras {
namespace monitoring {
namespace plugins {
namespace common {
namespace memoryplugin {

int counter = 0;

MemoryPlugin* MemoryPlugin::instance = 0;
agentCoreFunctions MemoryPlugin::aCF;

MemoryPlugin::MemoryPlugin(uint32 provID):
		provID(provID), noFailures(false){
}

MemoryPlugin* MemoryPlugin::getInstance() {
		return instance;
}

MemoryPlugin::~MemoryPlugin(){}

int MemoryPlugin::start() {
	aCF.logMessage(debug, ">>>MemoryPlugin::start()");
	noFailures = true;
	aCF.logMessage(debug, "<<<MemoryPlugin::start()");
	return 0;
}

int MemoryPlugin::stop() {
	aCF.logMessage(debug, ">>>MemoryPlugin::stop()");
	aCF.logMessage(debug, "<<<MemoryPlugin::stop()");
	return 0;
}

pullsource* MemoryPlugin::createSource(agentCoreFunctions aCF, uint32 provID) {
	aCF.logMessage(fine, "[memory_os] Registering pull source");
	if(!instance) {
		MemoryPlugin::aCF = aCF;
		instance = new MemoryPlugin(provID);
	}
	return instance->createPullSource(0, "common_memory");
}

pullsource* MemoryPlugin::createPullSource(uint32 srcid, const char* name) {
		pullsource *src = new pullsource();
		src->header.name = name;
		std::string desc("Description for ");
		desc.append(name);
		src->header.description = NewCString(desc);
		src->header.sourceID = srcid;
		src->next = NULL;
		src->header.capacity = DEFAULT_CAPACITY;
		src->callback = pullWrapper;
		src->complete = pullCompleteWrapper;
		src->pullInterval = MEMSOURCE_PULL_INTERVAL; // seconds
		return src;
}

monitordata* MemoryPlugin::OnRequestData() {
  aCF.logMessage(debug, ">>>MemoryPlugin::OnRequestData");
	monitordata *data = new monitordata;
	data->provID = provID;
	data->size = 0;
	data->data = NULL;

	data->persistent = false;
	data->sourceID = 0;

	std::stringstream ss;

	ss << MEMORY_SOURCE << COMMA;
	ss << getTime() << COMMA;
	ss << TOTAL_MEMORY    << EQUALS << getTotalPhysicalMemorySize()   << COMMA;
	ss << PHYSICAL_MEMORY << EQUALS << getProcessPhysicalMemorySize() << COMMA;
	ss << PRIVATE_MEMORY  << EQUALS << getProcessPrivateMemorySize()  << COMMA;
	ss << VIRTUAL_MEMORY  << EQUALS << getProcessVirtualMemorySize()  << COMMA;
	ss << FREE_PHYSICAL_MEMORY << EQUALS << getFreePhysicalMemorySize() << std::endl;

	std::string memorydata = ss.str();

	int len = memorydata.length();
	char* sval = new char[len + 1];
	if (sval) {
		strcpy(sval, memorydata.c_str());

		data->size = len;
		data->data = sval;

	}
	aCF.logMessage(debug, "<<<MemoryPlugin::OnRequestData");

	return data;
}

void MemoryPlugin::OnComplete(monitordata* data) {
	if (data != NULL) {
		if (data->data != NULL) {
			delete[] data->data;
		}
		delete data;
	}
}

/*****************************************************************************
 * CALLBACK WRAPPERS
 *****************************************************************************/

monitordata* pullWrapper() {
		return MemoryPlugin::getInstance()->OnRequestData();
}

void pullCompleteWrapper(monitordata* data) {
	MemoryPlugin::getInstance()->OnComplete(data);
}

/*****************************************************************************
 * FUNCTIONS EXPORTED BY THE LIBRARY
 *****************************************************************************/

extern "C" {
pullsource* ibmras_monitoring_registerPullSource(agentCoreFunctions aCF, uint32 provID) {
	aCF.logMessage(debug, "[memory_os] Registering pull source");
	pullsource *src = MemoryPlugin::createSource(aCF, provID);
	return src;
}

int ibmras_monitoring_plugin_init(const char* properties) {
	return 0;
}

int ibmras_monitoring_plugin_start() {
	MemoryPlugin::aCF.logMessage(fine, "[memory_os] Starting");
	return 0;
}

int ibmras_monitoring_plugin_stop() {
	MemoryPlugin::aCF.logMessage(fine, "[memory_os] Stopping");
	return 0;
}

const char* ibmras_monitoring_getVersion() {
		return PLUGIN_API_VERSION;
}
}

/*****************************************************************************
 * PLATFORM DEPENDENT CODE
 *****************************************************************************/


int64 MemoryPlugin::getProcessPhysicalMemorySize() {
#if defined(__linux__)
        /* Read rss field from /proc/<pid>/stat as per 'man proc'. */
#define RSS_FIELD_INDEX 23
        long rss;

        if (1 == readProcStatField(RSS_FIELD_INDEX, "%ld", &rss))
        {
                /* NOTE: This is accurate even in the context of huge pages. */
                return(int64)rss * sysconf(_SC_PAGESIZE);
        }
#undef RSS_FIELD_INDEX

#elif defined(__MACH__) || defined(__APPLE__)
	struct task_basic_info t_info;
	mach_msg_type_number_t t_info_count = TASK_BASIC_INFO_COUNT;
	task_info(current_task(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
	size_t size = t_info.resident_size;
	return size;

#elif defined(AIXPPC)
        /*
         * There is no API on AIX to get the rss of the shared memory used by this process.
         * If such an API was available, this function should return the following:
         *
         *   sharedRss + (pe.pi_trss + pe.pi_drss)*4096
         *
         * NOTE: pi_trss and pi_drss are always in 4K units regardless of pi_text_l2psize.
         */
#elif defined(WINDOWS)
        PROCESS_MEMORY_COUNTERS info;

        info.cb = sizeof(info);
        if (0 != GetProcessMemoryInfo(GetCurrentProcess(), &info, sizeof(info)))
        {
                return info.WorkingSetSize;
        }

#endif
        return -1;

}

int64 MemoryPlugin::getProcessPrivateMemorySize() {

#if defined(__linux__)
        /*
         * Read shared field from /proc/<pid>/statm as per 'man proc'.
         * Return difference between virtual memory size and shared.
         */
#define SHARED_FIELD_INDEX 2
        char buf[512];

        if (-1 != readProcFile("statm", buf, sizeof(buf)))
        {
                const char *str = skipFields(buf, SHARED_FIELD_INDEX);

                if (NULL != str)
                {
                        long shared;
                        if (1 == sscanf(str, "%ld", &shared))
                        {
                                int64 vsize = getProcessVirtualMemorySize();
                                if (-1 != vsize)
                                {
                                        int64 priv = vsize - ((int64)shared * sysconf(_SC_PAGESIZE));
                                        return(priv > 0 ? priv : -1);
                                }
                        }
                }
        }
#undef SHARED_FIELD_INDEX
#elif defined(AIXPPC)
        struct procentry64 pe;
        pid_t pid = getpid();

        if (1 == getprocs64((struct procentry64*)&pe, sizeof(pe), NULL, 0, &pid, 1))
        {
                /* NOTE: pi_dvm is always in 4K units regardless of pi_data_l2psize. */
                int64 size = (int64)pe.pi_tsize + (int64)pe.pi_dvm * 4096;

                return(size > 0 ? size : -1);
        }

#elif defined(__MACH__) || defined(__APPLE__)

#elif defined(WINDOWS)

        //IBMRAS_DEBUG(debug, ">>MEMPullSource::getProcessPrivateMemorySizeImpl()");

        PROCESS_MEMORY_COUNTERS_EX procMemCount;

        bool result = GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&procMemCount), sizeof(PROCESS_MEMORY_COUNTERS_EX));

        if(result) {
                return procMemCount.PrivateUsage > 0 ? procMemCount.PrivateUsage : -1;
        }
        return -1;

#endif
       // IBMRAS_DEBUG(debug, "<<MEMPullSource::getProcessPrivateMemorySizeImpl()[ERROR]");
        return -1;
}

int64  MemoryPlugin::getProcessVirtualMemorySize() {
#if defined(__linux__)
        /* Read vsize field from /proc/<pid>/stat as per 'man proc'. */
#define VSIZE_FIELD_INDEX 22
        unsigned long vsize;

        if (1 == readProcStatField(VSIZE_FIELD_INDEX, "%lu", &vsize))
        {
                return(int64)(vsize > 0 ? vsize : -1);
        }
#undef VSIZE_FIELD_INDEX
#elif defined(__MACH__) || defined(__APPLE__)
	struct task_basic_info t_info;
	mach_msg_type_number_t t_info_count = TASK_BASIC_INFO_COUNT;
	task_info(current_task(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
	size_t size = t_info.virtual_size;
	return size;
#elif defined(AIXPPC)
        /* There is no API on AIX to get shared memory usage for the process. If such an
         * API existed, we could return getProcessPrivateMemorySize() + sharedSize here.
         *
         * Note: Iterating through /proc/<pid>/map and looking at the pages that are
         * not marked MA_SHARED does not account for shared code pages when in fact
         * command-line AIX utilities (such as svmon) do show that pages are shared.
         */
#elif defined(WINDOWS)
        PROCESS_MEMORY_COUNTERS info;

        info.cb = sizeof(info);
        if (0 != GetProcessMemoryInfo(GetCurrentProcess(), &info, sizeof(info)))
        {
                return(int64)info.PagefileUsage;
        }
#endif
        return -1;
}

int64 MemoryPlugin::getFreePhysicalMemorySize() {
#if defined(__linux__)
        /* NOTE: This is accurate even in the context of huge pages. */
        return(int64)sysconf(_SC_AVPHYS_PAGES) * sysconf(_SC_PAGESIZE);

#elif  defined(__MACH__) || defined(__APPLE__)

        vm_size_t pageSize = 4096;
        mach_port_t myHost = mach_host_self();

        if(host_page_size(myHost, &pageSize) != KERN_SUCCESS) {
        	aCF.logMessage(warning, "Failed to get pagesize, default set to 4K");
        }
        vm_statistics64_data_t vm_stat;
        unsigned int count = HOST_VM_INFO64_COUNT;
        kern_return_t ret;
        ret = host_statistics64(myHost, HOST_VM_INFO64, reinterpret_cast<host_info64_t>(&vm_stat), &count);
        if (( ret != KERN_SUCCESS)) {
        	aCF.logMessage(warning, "Failed to get host statistics");
        	return -1;
        }
        return vm_stat.free_count*pageSize;

#elif defined(AIXPPC)
        /* NOTE: This works on AIX 5.3 and later. */
        IDATA numPageSizes = vmgetinfo(NULL, VMINFO_GETPSIZES, 0);

        if (numPageSizes > 0)
        {
                psize_t *pageSizes = (psize_t*)alloca(numPageSizes*sizeof(psize_t));
                IDATA numPageSizesRetrieved = vmgetinfo(pageSizes, VMINFO_GETPSIZES, numPageSizes);

                if (numPageSizes == numPageSizesRetrieved)
                {
                        int64 size = 0;
                        IDATA i;

                        for (i = 0; i < numPageSizes; i++)
                        {
                                struct vminfo_psize pageSize;

                                pageSize.psize = pageSizes[i];
                                if (0 == vmgetinfo(&pageSize, VMINFO_PSIZE, sizeof(pageSize)))
                                {
                                        size += (int64)pageSize.psize * pageSize.numfrb;
                                }
                        }
                        return(size > 0 ? size : -1);
                }
        }
        return -1;
#elif defined(WINDOWS)
        MEMORYSTATUSEX statex;

        statex.dwLength = sizeof(statex);
        if (0 != GlobalMemoryStatusEx(&statex))
        {
                return statex.ullAvailPhys;
        }
        return -1;
#else
        return -1;
#endif
}

int64 MemoryPlugin::getTotalPhysicalMemorySize() {
#if defined (_AIX)
	return (int64)(sysconf(_SC_AIX_REALMEM) * 1024);

#elif defined(__linux__) ||defined(__MACH__)&&defined(_SC_PAGESIZE)&&defined(_SC_PHYS_PAGES) ||defined(__APPLE__)&&defined(_SC_PAGESIZE)&&defined(_SC_PHYS_PAGES)
	IDATA pagesize, num_pages;

    pagesize = sysconf(_SC_PAGESIZE);
    num_pages = sysconf(_SC_PHYS_PAGES);

	if (pagesize == -1 || num_pages == -1) {
		return 0;
    } else {
		return (int64) pagesize *num_pages;
	}
	/*
	 * There is a bug in OSX Mavericks which may cause the compilation to fail
	 * due to _SC_PHYS_PAGES not being defined in <unistd.h> so we have to resource
	 * to sysctl if that's the case
	 */
#elif defined(__MACH__)|| defined(__APPLE__)//OSX


#if defined(CTL_HW) && defined(HW_MEMSIZE) //64Bit
	int mib[2] = {CTL_HW, HW_MEMSIZE};
	unsigned long physicalMemSize;
	size_t len = sizeof(physicalMemSize);
	if(!sysctl(mib, 2, &physicalMemSize, &len, NULL, 0)) {
		return physicalMemSize;
	}else {
		aCF.logMessage(debug, strerror(errno));
		return -1;
	}
#elif defined(CTL_HW) && defined(HW_PHYSMEM) //32Bit
	int mib[2] = {CTL_HW, HW_PHYSMEM};
		unsigned long physicalMemSize;
		size_t len = sizeof(physicalMemSize);
		if(!sysctl(mib, 2, &physicalMemSize, &len, NULL, 0)) {
			return physicalMemSize;
		}else {
			aCF.logMessage(debug, strerror(errno));
			return -1;
		}
#endif

#elif defined (_WINDOWS)
	MEMORYSTATUSEX statex;

	statex.dwLength = sizeof(statex);
	if (0 != GlobalMemoryStatusEx(&statex))
	{
		return statex.ullTotalPhys;
	}
	return -1;
#elif defined(_S390)
	/* Get_Physical_Memory returns "SIZE OF ACTUAL REAL STORAGE ONLINE IN 'K'" */
	return Get_Physical_Memory() * 1024;
#else
	return -1;
#endif
}


#if defined(__linux__)
/**
 * Opens file at /proc/<pid>/<fname> for reading.
 *
 * @param[in] fname  Name of file to open.
 *
 * @return File descriptor of the opened file or -1 on failure.
 */
static IDATA openProcFile(const char *fname)
{
        char proc[MAXPATHLEN];

        snprintf(proc, sizeof(proc), "/proc/%d/%s", getpid(), fname);

        return open(proc,O_RDONLY);
}

/**
 * Read proc file at /proc/<pid>/<fname> into buf of size nbytes.
 * Null-terminates the buffer so it can be treated as a string.
 *
 * @param[in]  fname  Name of file to open.
 * @param[out] buf    Buffer to read file into.
 * @param[in]  nbytes Size of buffer.
 *
 * @return Returns number of bytes read excluding null-terminator
 *         or -1 on failure.
 */
static IDATA readProcFile(const char *fname, char *buf, UDATA nbytes)
{
        IDATA ret = -1;
        IDATA fd = openProcFile(fname);

        if (-1 != fd)
        {
                ret = 0;
                /* Read up to (nbytes - 1) bytes to save space for the null terminator. */
                while (nbytes - ret > 1)
                {
                        IDATA nread = read(fd, buf + ret, nbytes - ret - 1);

                        if (nread <= 0)
                        break;
                        ret += (UDATA)nread;
                }
                buf[ret] = '\0';
                close(fd);
        }
        return ret;
}

/**
 * Gets the running process name as null-terminated string.
 *
 * @param[out] name        Buffer to store name of the process.
 * @param[in]  nameLength  Length of the name buffer.
 *
 * @return Pointer to name on success or NULL on error.
 */
static char* getProcessName(char *name, UDATA nameLength)
{
        /*
         * Read the first line from /proc/<pid>/status and parse
         * the process name from it.
         *
         * It would be nice to use prctl() with PR_GET_NAME - but
         * it is only supported on kernel version 2.6.11 and later.
         */
#define PROC_NAME_PREFIX "Name:\t"
        char *ret = NULL;
        char buf[128];

        if (-1 != readProcFile("status", buf, sizeof(buf)))
        {
                if (0 == strncmp(buf, PROC_NAME_PREFIX, sizeof(PROC_NAME_PREFIX) - 1))
                {
                        UDATA i;
                        char *from = buf + sizeof(PROC_NAME_PREFIX) - 1;

                        for (i = 0; (i < nameLength - 1) && ('\0' != from[i]) && ('\n' != from[i]); i++)
                        {
                                name[i] = from[i];
                        }
                        name[i] = '\0';
                        ret = name;
                }
        }
        return ret;
#undef PROC_NAME_PREFIX
}

/**
 * Skips n number of space-separator fields in str. The string
 * must not begin with whitespace.
 *
 * @param[in] str Null-terminated string that will be scanned.
 * @param[in] n   Number of fields to skip, must be positive.
 *
 * @return Pointer to the location in the string after the skipped
 *         fields, or NULL if end of string was encountered.
 */
static const char* skipFields(const char *str, UDATA n)
{
        str++;
        while (('\0' != *str) && (n > 0))
        {
                if (isspace(*str))
                {
                        n--;
                }
                str++;
        }
        return(n != 0 ? NULL : str);
}


/**
 * Opens /proc/<pid>/stat file and reads the field at position index
 * from the file as sscanf would. Field index must be >= 2. Returns
 * result of sscanf (i.e. number of fields read), or -1 on failure.
 *
 * @param[in]  index  Index of the field to be read.
 * @param[in]  format Format string for field to be read.
 * @param[out] ...    Field(s) to be read as per format.
 *
 * @return Number of fields read, or -1 on failure.
 */
//static IDATA readProcStatField(UDATA index, const char *format, ...)
//__attribute__((format(scanf,3,4)));
static IDATA readProcStatField(UDATA index, const char *format, ...)
{
        IDATA ret = -1;
        char buf[512];

        if (-1 != readProcFile("stat", buf, sizeof(buf)))
        {
                /*
                 * The second field in /proc/<pid>/stat is the process name
                 * surrounded by parentheses. Unfortunately, the process
                 * name can have both spaces and parentheses in it, neither
                 * of which are escaped. Thus, to parse the file correctly,
                 * we must get the process name in order to be able to skip
                 * it in the /proc/<pid>/stat file.
                 */
                char processName[64];

                if (NULL != getProcessName(processName, sizeof(processName)))
                {
                        char expected[128];
                        size_t length = (size_t)snprintf(expected, sizeof(expected),
                                        "%d (%s) ", getpid(), processName);

                        /* Verify that the start of the file matches what we expected. */
                        if (0 == memcmp(buf, expected, length))
                        {
                                const char *str = skipFields(buf + length, index - 2);

                                if (NULL != str)
                                {
                                        va_list ap;
                                        va_start(ap, format);
                                        ret = vsscanf(str, format, ap);
                                        va_end(ap);
                                }
                        }
                }
        }

        return ret;
}
#endif

int64 MemoryPlugin::getTime() {
#if defined(__linux__) || defined(_AIX) || defined(__MACH__) || defined(__APPLE__)
        struct timeval tv;
        gettimeofday(&tv, NULL);
        return ((int64) tv.tv_sec)*1000 + tv.tv_usec/1000;
#elif defined(_WINDOWS)
        LONGLONG time;
       	GetSystemTimeAsFileTime( (FILETIME*)&time );
       	return (int64) ((time - 116444736000000000) /10000);
#elif defined(_S390)
	int64 millisec = MAXPREC() / 8000;
	return millisec;
#else
	return -1;
#endif
}

char* MemoryPlugin::NewCString(const std::string& s) {
		char *result = new char[s.length() + 1];
		std::strcpy(result, s.c_str());
		return result;
}


} //memoryplugin
} //common
} //plugins
} //monitoring
} //ibmras

