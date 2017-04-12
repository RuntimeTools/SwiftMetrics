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

#include "FileUtils.h"
#include "../logging.h"

#if defined(WINDOWS)
#include <windows.h>
#include <tchar.h>
#else
#include <dlfcn.h>
#include <sys/stat.h>
#include <errno.h>
#include <cstring>
#endif

namespace ibmras {
namespace common {
namespace util {



IBMRAS_DEFINE_LOGGER("FileUtils");

bool ibmras::common::util::FileUtils::createDirectory(std::string& path) {
	IBMRAS_DEBUG(debug, ">>>HLConnector::createDirectory");
	bool created = false;

	const char* pathName = path.c_str();

#if defined(WINDOWS)
	DWORD dirAttr;
	IBMRAS_DEBUG_1(debug, "Creating directory: %s", pathName);
	dirAttr = GetFileAttributes(reinterpret_cast<LPCTSTR>(pathName));

	if(INVALID_FILE_ATTRIBUTES == dirAttr) {
		switch (GetLastError()) {
			case ERROR_PATH_NOT_FOUND:
				IBMRAS_DEBUG(warning, "The directory was not found");
				IBMRAS_DEBUG_1(debug, "Creating directory: %s", pathName);
				if(!CreateDirectory(reinterpret_cast<LPCTSTR>(pathName), NULL)) {
					switch (GetLastError()) {
						//if the directory already exists we will use it instead of the current one.
						case ERROR_ALREADY_EXISTS:
							IBMRAS_DEBUG(warning, "The specified directory already exists.");
							created = true;
							break;
						case ERROR_PATH_NOT_FOUND:
							IBMRAS_DEBUG(warning, "The system cannot find the path specified.");
							break;
					}
				} else {
					created = true;
				}
				break;
			case ERROR_INVALID_NAME:
			IBMRAS_DEBUG(warning, "The filename, directory name, or volume label syntax is incorrect");
			break;
			case ERROR_BAD_NETPATH:
			IBMRAS_DEBUG(warning, "The network path was not found.");
			break;
			default:
			IBMRAS_DEBUG(warning, "The directory could not be found, permissions?.");
			IBMRAS_DEBUG_1(debug, "Creating directory: %s", pathName);
			if(!CreateDirectory(reinterpret_cast<LPCTSTR>(pathName), NULL)) {
				switch (GetLastError()) {
					case ERROR_ALREADY_EXISTS:
					IBMRAS_DEBUG(warning, "The specified directory already exists.");
					created = true;
					break;
					case ERROR_PATH_NOT_FOUND:
					IBMRAS_DEBUG(warning, "The system cannot find the path specified.");
					break;
				}
			} else {
				created = true;
			}
		}
	}

#else
	struct stat dir;
	IBMRAS_DEBUG_1(debug, "Pathname...%s\n", pathName);
	if (stat(pathName, &dir)) {
		IBMRAS_DEBUG_1(debug, "Directory does not exist, creating...%s\n", pathName);
		if (mkdir(pathName, S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH)) {
			IBMRAS_DEBUG_1(debug, "Directory could not be created: ", strerror(errno));
			if(EEXIST == errno) {
				IBMRAS_DEBUG_1(debug, "Directory % already existed", pathName);
				created = true;
			}
		} else {
			IBMRAS_DEBUG_1(debug, "Directory %s was created: ", pathName);
			created = true;
		}
	} else {
		IBMRAS_DEBUG(debug, "stat() returned 0, we'll check whether it was an existing directory");
		if(S_ISDIR(dir.st_mode)) {
			created = true;
		}
	}
#endif
	IBMRAS_DEBUG(debug, "<<<HLConnector::createDirectory()");

	return created;
}

//bool ibmras::common::util::FileUtils::isWriteable(std::string dir) {
//	return true;
//
//}

}//util
}//common
}//ibmras
