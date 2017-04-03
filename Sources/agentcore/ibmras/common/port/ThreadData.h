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


#ifndef ibmras_common_port_threaddata_h
#define ibmras_common_port_threaddata_h

#include <vector>
#include <string>
#include "../../monitoring/Typesdef.h"
#include "AgentExtensions.h"


namespace ibmras {
namespace common {
namespace port {


class ThreadData;											/* forward declaration of ThreadData class */
typedef void* (*THREAD_CALLBACK)(ThreadData*);				/* shortcut definition for the thread  callback */

/* provides the encapsulation of different thread semantics for each platform */
class DECL ThreadData {
public:
	ThreadData(THREAD_CALLBACK callback);
	ThreadData(THREAD_CALLBACK callback, THREAD_CALLBACK stopMethod);
	~ThreadData(){}
	void setArgs(void* args);
	void* getArgs();
	THREAD_CALLBACK getCallback();
	THREAD_CALLBACK getStopMethod();
	bool hasStopMethod();
private:
	uintptr_t handle;								/* handle to underlying OS thread */
	THREAD_CALLBACK callback;						/* callback to make */
	THREAD_CALLBACK stopmethod;						/* method to call when stopping */
	bool hasstopmethod;								/* flag for indicating prescence of stop method */
	void* args;
};


DECL uintptr_t createThread(ThreadData *data);				/* create a thread and start it with specified callback and args */
void exitThread(void *val);								/* exit current thread with an optional return value */
DECL void sleep(uint32 seconds);								/* sleep the current thread */
void stopAllThreads();									/* Stops all threads */

}
}
}	/*end of namespace port */

#endif /* ibmras_common_port_threaddata_h */
