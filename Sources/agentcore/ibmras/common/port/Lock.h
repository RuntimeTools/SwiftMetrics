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


#ifndef ibmras_common_port_lock_h
#define ibmras_common_port_lock_h

#include <vector>
#include <string>
#include "AgentExtensions.h"

#ifndef NULL
#define NULL 0
#endif

#if defined(_WINDOWS)
#define LOCK_FAIL -1

#elif defined(__linux__)
#define LOCK_FAIL -1

#elif defined(_AIX)

#elif defined(_ZOS)
#define LOCK_FAIL -1
#elif defined(__MACH__) || defined(__APPLE__)
#define LOCK_FAIL -1
#endif

namespace ibmras {
namespace common {
namespace port {

/* different type of lock functionality required by threads */
class DECL Lock {
public:
	Lock();													/* default constructor */
	int acquire();											/* acquire the lock associated with this class */
	int release();											/* release the lock */
	void destroy();											/* Detroy / release the platform lock */
	bool isDestroyed();										/* true if the underlygin platform lock has been destroyed */
	~Lock();												/* destructor to allow lock release */
private:
	void* lock;												/* platform lock structure */
};

}
}
}	/*end of namespace port */

#endif /* ibmras_common_port_lock_h */
