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
#define _UNIX03_SOURCE
#endif

#include "Plugin.h"
#include "../common/logging.h"

#include <stdlib.h>

#if defined(WINDOWS)
#include <windows.h>
#include <tchar.h>
#include <strsafe.h>
#else
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#endif

namespace ibmras {
namespace monitoring {

IBMRAS_DEFINE_LOGGER("Plugin")
;

/* these names are produced by gcc and may not be the same for all compilers */
const char* SYM_INIT = "ibmras_monitoring_plugin_init";
const char* SYM_REGISTER_PUSH_SOURCE = "ibmras_monitoring_registerPushSource";
const char* SYM_REGISTER_PULL_SOURCE = "ibmras_monitoring_registerPullSource";
const char* SYM_STOP = "ibmras_monitoring_plugin_stop";
const char* SYM_START = "ibmras_monitoring_plugin_start";
const char* SYM_CONNECTOR_FACTORY = "ibmras_monitoring_getConnector";
const char* SYM_RECEIVER_FACTORY = "ibmras_monitoring_getReceiver";
const char* SYM_RECEIVE_MESSAGE = "ibmras_monitoring_receiveMessage";
const char* SYM_VERSION = "ibmras_monitoring_getVersion";

Plugin::Plugin() :
		name(""), init(NULL), push(NULL), pull(NULL), start(NULL), stop(NULL), confactory(
				NULL), recvfactory(NULL), receiveMessage(NULL), type(0), version(0), getVersion(NULL) {
}

std::vector<Plugin*> Plugin::scan(const std::string& dir) {

	std::vector<Plugin*> plugins;

	IBMRAS_DEBUG_1(fine, "Processing plugin path: %s", dir.c_str());

#if defined(WINDOWS)
	WIN32_FIND_DATA ffd;
	LARGE_INTEGER filesize;
	TCHAR szDir[MAX_PATH];
	HANDLE hFind = INVALID_HANDLE_VALUE;
	DWORD dwError = 0;
	HINSTANCE handle;

	TCHAR* path = (TCHAR*) dir.c_str(); /* cast to the unicode or ascii version */

	size_t length_of_arg;
	StringCchLength(path, MAX_PATH, &length_of_arg);
	if (length_of_arg > (MAX_PATH - 3)) {
		IBMRAS_DEBUG(fine, "The path is too long");
		return plugins;
	}

	StringCchCopy(szDir, MAX_PATH, path);
	StringCchCat(szDir, MAX_PATH, TEXT("\\*.dll"));

	IBMRAS_DEBUG_1(finest, "Scanning %s", szDir);

	hFind = FindFirstFile(szDir, &ffd);

	if (INVALID_HANDLE_VALUE == hFind) {
		IBMRAS_DEBUG(warning, "Unable to access the contents");
		return plugins;
	}

	do {
		if (!(ffd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
			StringCchCopy(szDir, MAX_PATH, path);
			StringCchCat(szDir, MAX_PATH, TEXT("\\"));
			StringCchCat(szDir, MAX_PATH, ffd.cFileName);

			Plugin *plugin = processLibrary(szDir);
			if (plugin != NULL) {
				IBMRAS_LOG_2(fine, "%s, version %s", (plugin->name).c_str(), (plugin->getVersion()));
				plugins.push_back(plugin);
			}
		}
	}while (FindNextFile(hFind, &ffd) != 0);

	dwError = GetLastError();

	if (dwError != ERROR_NO_MORE_FILES) {
		IBMRAS_DEBUG(fine, "Error while traversing directory");
	}

	FindClose(hFind);

#else

	struct dirent *entry;

	DIR *dp = opendir(dir.c_str());

	if (dp == NULL) {
		IBMRAS_DEBUG_1(fine, "Warning, unable to open directory %s", dir.c_str());
		return plugins;
	}

	while ((entry = readdir(dp)) != NULL) {
		if (entry->d_name[0] != '.') {

			std::string filePath = dir;
			filePath += "/";
			filePath += entry->d_name;
#if defined(__MACH__) || defined(__APPLE__)
       std::size_t found = filePath.rfind(".dylib", filePath.size() - 6);
       if (found != std::string::npos) {
          Plugin *plugin = processLibrary(filePath);
         if (plugin != NULL) {
           IBMRAS_LOG_2(fine, "%s, version %s", (plugin->name).c_str(), (plugin->getVersion()));
           plugins.push_back(plugin);
         }
       }
#else
			Plugin *plugin = processLibrary(filePath);
			if (plugin != NULL) {
				IBMRAS_LOG_2(fine, "%s, version %s", (plugin->name).c_str(), (plugin->getVersion()));
				plugins.push_back(plugin);
			}
#endif
		}
	}
	closedir(dp);

#endif

	return plugins;

}

Plugin* Plugin::processLibrary(const std::string &filePath) {

	Plugin* plugin = NULL;
	IBMRAS_DEBUG_1(fine, "Processing plugin library: %s", filePath.c_str());

	ibmras::common::util::LibraryUtils::Handle handle =
			ibmras::common::util::LibraryUtils::openLibrary(filePath.c_str());
	if (handle.isValid()) {

		void* init = ibmras::common::util::LibraryUtils::getSymbol(handle,
				SYM_INIT);
		void* push = ibmras::common::util::LibraryUtils::getSymbol(handle,
				SYM_REGISTER_PUSH_SOURCE);
		void* pull = ibmras::common::util::LibraryUtils::getSymbol(handle,
				SYM_REGISTER_PULL_SOURCE);
		void* start = ibmras::common::util::LibraryUtils::getSymbol(handle,
				SYM_START);
		void* stop = ibmras::common::util::LibraryUtils::getSymbol(handle,
				SYM_STOP);
		void* getVersion = ibmras::common::util::LibraryUtils::getSymbol(handle,
				SYM_VERSION);
		void* connectorFactory = ibmras::common::util::LibraryUtils::getSymbol(
				handle, SYM_CONNECTOR_FACTORY);
		void* receiverFactory = ibmras::common::util::LibraryUtils::getSymbol(
				handle, SYM_RECEIVER_FACTORY);
		void* receiveMessage = ibmras::common::util::LibraryUtils::getSymbol(
				handle, SYM_RECEIVE_MESSAGE);

		IBMRAS_DEBUG_4(fine, "Library %s: start=%p stop=%p getVersion=%p", filePath.c_str(), start, stop, getVersion);

		/* External plugins MUST implement both start, stop and getVersion */
		if (start && stop && getVersion) {
			IBMRAS_DEBUG_1(fine, "Library %s was successfully recognised", filePath.c_str());
			plugin = new Plugin;

			plugin->name = filePath;
			plugin->handle = handle;

			plugin->init =reinterpret_cast<PLUGIN_INITIALIZE>(init);

			plugin->pull = reinterpret_cast<pullsource* (*)(agentCoreFunctions, uint32)>(pull);

			plugin->push = reinterpret_cast<pushsource* (*)(agentCoreFunctions, uint32)>(push);

			plugin->stop = reinterpret_cast<int (*)()>(stop);

			plugin->start = reinterpret_cast<int (*)()>(start);

			plugin->getVersion = reinterpret_cast<const char* (*)()>(getVersion);

			plugin->confactory = reinterpret_cast<CONNECTOR_FACTORY>(connectorFactory);

			plugin->recvfactory = reinterpret_cast<RECEIVER_FACTORY>(receiverFactory);

			plugin->receiveMessage = reinterpret_cast<RECEIVE_MESSAGE>(receiveMessage);
			
			if (plugin->recvfactory && plugin->receiveMessage) {
				IBMRAS_DEBUG_4(warning, "Library %s: Both %s and %s are defined. Ignoring %s.", filePath.c_str(), SYM_RECEIVER_FACTORY, SYM_RECEIVE_MESSAGE, SYM_RECEIVER_FACTORY);
				plugin->receiveMessage = NULL;
			}

			plugin->setType();
		} else {
			/* not a plugin so close the handle	*/
			ibmras::common::util::LibraryUtils::closeLibrary(handle);
		}
	} else {
#if defined(WINDOWS)

#else
		IBMRAS_DEBUG_2(fine, "Not valid handler for library candidate %s. \ndlerror output: \"%s\"", filePath.c_str(), dlerror());
#endif
	}
	return plugin;
}

void Plugin::unload() {
	if (handle.isValid()) {
		ibmras::common::util::LibraryUtils::closeLibrary(handle);
	}
}

void Plugin::setType() {
	type = plugin::none;
	if (pull || push) {
		type = plugin::data;
	}
	if (confactory) {
		type = type | plugin::connector;
	}
	if (recvfactory || receiveMessage) {
		type = type | plugin::receiver;
	}
}

}
}

