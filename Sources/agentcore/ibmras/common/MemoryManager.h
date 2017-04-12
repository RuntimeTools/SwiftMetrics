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

#ifndef ibmras_common_memorymanager_h
#define ibmras_common_memorymanager_h

/*
 * Memory management functionality
 */

#include "../monitoring/Typesdef.h"
#include "AgentExtensions.h"

namespace ibmras {
namespace common {

class MemoryManager {

public:

	MemoryManager();
	virtual ~MemoryManager();

	virtual unsigned char* allocate(uint32 size);
	virtual void deallocate(unsigned char**);

protected:
private:

};

namespace memory {

MemoryManager* getDefaultMemoryManager();
bool setDefaultMemoryManager(MemoryManager* manager);

DECL unsigned char* allocate(uint32 size);
DECL void deallocate(unsigned char**);

}

}
}

#endif /* ibmras_common_memorymanager_h */
