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
#define _XOPEN_SOURCE_EXTENDED 1
#undef _ALL_SOURCE
#endif

#include "sysUtils.h"

#if defined(WINDOWS)
	#include <windows.h>
//    #include <winsock2.h>
	#include <Psapi.h>
#elif defined(__linux__) || defined(__MACH__) || defined(__APPLE__)
#include <sys/time.h>
#elif defined(AIX)
#include <sys/time.h>
#elif defined(_ZOS)
#include <sys/time.h>
#endif

#include <ctime>


namespace ibmras {
namespace common {
namespace util {

unsigned long long getMilliseconds() {
	unsigned long long millisecondsSinceEpoch;
#if defined(WINDOWS)

	SYSTEMTIME st;
	GetSystemTime(&st);

	millisecondsSinceEpoch = time(NULL)*1000+st.wMilliseconds;

#else
		struct timeval tv;
	gettimeofday(&tv, NULL);

	millisecondsSinceEpoch =
	    (unsigned long long)(tv.tv_sec) * 1000 +
	    (unsigned long long)(tv.tv_usec) / 1000;
#endif
	return millisecondsSinceEpoch;
}

}/*end of namespace util*/
}/*end of namespace common*/
} /*end of namespace ibmras*/


