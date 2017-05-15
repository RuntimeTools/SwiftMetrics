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

#include "LibraryUtils.h"

#if defined(WINDOWS)
#include <windows.h>
#include <tchar.h>
#include <strsafe.h>
const char PATHSEPARATOR = '\\';
#else
#include <dlfcn.h>
#include <errno.h>
const char PATHSEPARATOR = '/';
#endif


namespace ibmras {
namespace common {
namespace util {

void* LibraryUtils::getSymbol(Handle libHandle, const std::string& symbolName) {

	void *symbol = NULL;

#if defined(WINDOWS)
	symbol = (void*) GetProcAddress(libHandle.handle, symbolName.c_str());
#else
	/* Unix platforms */
	symbol = dlsym(libHandle.handle, symbolName.c_str());
#endif

	return symbol;

}

ibmras::common::util::LibraryUtils::Handle LibraryUtils::openLibrary(const std::string& lib) {

	Handle handle;
#if defined(WINDOWS)
	handle.handle = LoadLibrary(lib.c_str());
#else
#if defined(__MACH__) || defined(__APPLE__)
       // std::size_t found = lib.rfind(".dylib", lib.size() - 6);
      //  if (found == std::string::npos) {
      //     return Handle();
       // }
#endif
        handle.handle = dlopen(lib.c_str(), RTLD_LAZY);
#endif
	return handle;
}

void LibraryUtils::closeLibrary(Handle libHandle) {

#if defined(WINDOWS)
	FreeLibrary(libHandle.handle);
#else
	dlclose(libHandle.handle);
#endif
	libHandle.handle = NULL;
}

std::string LibraryUtils::getLibraryLocation(const void* func) {
	std::string path;

#if defined (WINDOWS)
#elif defined(AIX)
#elif defined(_ZOS)
#else
	Dl_info dlInfo;
	int rc = dladdr(func, &dlInfo);
	if (rc != 0) {
		path = dlInfo.dli_fname;
	}

#endif
	return path;
}

std::string LibraryUtils::getLibraryDir(const std::string &library, const void* func) {
	std::string path;
#if defined (WINDOWS)
	path = getLibraryLocation(library);
#else
	path = getLibraryLocation(func);
#endif
	size_t pos = path.find_last_of(PATHSEPARATOR);
	if (pos != std::string::npos) {
		path = path.substr(0, pos);
	}
	return path;
}

std::string LibraryUtils::getLibraryLocation(const std::string &library) {
	std::string path;

#if defined (WINDOWS)
	HMODULE hModule = GetModuleHandle(library.c_str());
	TCHAR dllPath[_MAX_PATH];
	GetModuleFileName(hModule, dllPath, _MAX_PATH);
	path = dllPath;
#else
#endif
	return path;
}

}
}
}
