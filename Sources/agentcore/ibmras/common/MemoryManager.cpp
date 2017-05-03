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


#include "MemoryManager.h"
#include "logging.h"
#include <string.h>

namespace ibmras {
namespace common {

IBMRAS_DEFINE_LOGGER("memory");

MemoryManager::MemoryManager() {
}


MemoryManager::~MemoryManager() {
}

unsigned char* MemoryManager::allocate(uint32 size) {
	unsigned char* memory = new (std::nothrow) unsigned char[size];
	if (memory == 0) {
		IBMRAS_LOG_1(warning, "Failed to allocate memory of size %d", size);
		return NULL;
	}

	memset(memory, 0, size);

	IBMRAS_DEBUG_2(debug, "Allocated %d at %p", size, (void*)memory);

	return memory;
}

void MemoryManager::deallocate(unsigned char** memoryPtr) {

	IBMRAS_DEBUG_1(debug, "Deallocate called for %p", (void*)memoryPtr);
	if (memoryPtr != NULL && *memoryPtr != NULL) {
		IBMRAS_DEBUG_1(debug, "Deallocating memory at %p", (void*)*memoryPtr);
		delete[] *memoryPtr;
		*memoryPtr = NULL;
	}
}

namespace memory {

static MemoryManager* defaultMemoryManager = NULL;

MemoryManager* getDefaultMemoryManager() {
	if (defaultMemoryManager == NULL) {
		defaultMemoryManager = new MemoryManager();
	}
	return defaultMemoryManager;
}

bool setDefaultMemoryManager(MemoryManager* manager) {
	if (defaultMemoryManager == NULL && manager != NULL) {
		defaultMemoryManager = manager;
		return true;
	}
	return false;
}

unsigned char* allocate(uint32 size) {
	return getDefaultMemoryManager()->allocate(size);
}

void deallocate(unsigned char** memoryPtr) {
	getDefaultMemoryManager()->deallocate(memoryPtr);
}

} /* namespace memory */


} /* namespace common */
} /* namespace ibmras */
