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
 * Functions that control thread behaviour
 */

#include "process.h"
#include "windows.h"
#include "stdio.h"
#include "../ThreadData.h"
#include "../Semaphore.h"
#include "../../logging.h"

namespace ibmras{
namespace common{
namespace port {

IBMRAS_DEFINE_LOGGER("Port");

typedef void *(*callback) (void *);

/* wrapper function to convert from void* to void return types */
void wrapper(void *params) {
	IBMRAS_DEBUG(fine,  "in thread.cpp->wrapper");
	ThreadData* data = reinterpret_cast<ThreadData*>(params);
	data->getCallback()(data);
}


uintptr_t createThread(ThreadData* data) {
	uintptr_t result;
	IBMRAS_DEBUG(fine,  "in thread.cpp->createThread");
	result = _beginthread(wrapper, 0, data);
	if(result) {
		return 0;	/* works = handle to thread, so convert to NULL for consistent semantics */
	}
	return 1;
}


void exitThread(void *val) {
	_endthread();
}

void sleep(uint32 seconds) {
	Sleep(1000 * seconds);
}

void stopAllThreads() {
	IBMRAS_DEBUG(fine,"in thread.cpp->stopAllThreads");
}

Semaphore::Semaphore(uint32 initial, uint32 max) {
	handle = new HANDLE;
	IBMRAS_DEBUG(fine,  "in thread.cpp creating CreateSemaphoreA");
	handle = CreateSemaphoreA(NULL, initial, max, NULL);
	if(handle == NULL) {
		IBMRAS_DEBUG_1(warning,  "Failed to create semaphore : error code %d", GetLastError());
		handle = NULL;
	}
}

void Semaphore::inc() {
	IBMRAS_DEBUG(finest,  "Incrementing semaphore ticket count");
	if(handle) {
		ReleaseSemaphore(handle,1,NULL);
	}
}

bool Semaphore::wait(uint32 timeout) {

	IBMRAS_DEBUG(finest,  "Semaphore::wait");
	DWORD retVal = WaitForSingleObject(handle, timeout * 1000);
	if ( !GetLastError()) {
		return (retVal == WAIT_OBJECT_0);
	}
	return false;

}

Semaphore::~Semaphore() {
	IBMRAS_DEBUG(finest,  "Semaphore::~Semaphore()");
	ReleaseSemaphore(handle,1,NULL);
	CloseHandle(handle);
}

}
}
}	/* end of namespace port */
