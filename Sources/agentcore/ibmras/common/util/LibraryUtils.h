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


#ifndef ibhmras_common_util_libraryutils_h
#define ibhmras_common_util_libraryutils_h

#if defined(WINDOWS)
#include <windows.h>
#else
#endif

#include <string>

namespace ibmras {
namespace common {
namespace util {

class LibraryUtils {

public:
	class Handle {
	public:
#if defined(WINDOWS)
		typedef HINSTANCE handle_type;
#else
		typedef void* handle_type;
#endif

		Handle() :
				handle(NULL) {
		}

		bool isValid() {return (handle != NULL); }
		handle_type handle;
	};

	static void* getSymbol(Handle libHandle, const std::string& symbol);
	static Handle openLibrary(const std::string &lib);
	static void closeLibrary(Handle libHandle);

	static std::string getLibraryDir(const std::string &library, const void* func);
	static std::string getLibraryLocation(const void* func);
	static std::string getLibraryLocation(const std::string &library);

};

}
}
}

#endif /* ibhmras_common_util_libraryutils_h */
