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

#include "pthread.h"
#include "time.h"
#include <semaphore.h>
#include <errno.h>

#include "../ThreadData.h"
#include "../Semaphore.h"
#include "../../logging.h"
#include <map>
#include <stack>
#include <list>
#include <cstdio>

namespace ibmras {
namespace common {
namespace port {

IBMRAS_DEFINE_LOGGER("Port");

std::list<pthread_cond_t> condMap;
std::stack<pthread_t> threadMap;
pthread_mutex_t condMapMux = PTHREAD_MUTEX_INITIALIZER;
pthread_mutex_t threadMapMux = PTHREAD_MUTEX_INITIALIZER;
bool stopping = false;

void* wrapper(void *params) {
	IBMRAS_DEBUG(fine,"in thread.cpp->wrapper");
	ThreadData* data = reinterpret_cast<ThreadData*>(params);
	void* result;
	if (data->hasStopMethod()) {
		IBMRAS_DEBUG(debug,"stopMethod present");
		pthread_cleanup_push(reinterpret_cast<void (*)(void*)>(data->getStopMethod()), data);
		IBMRAS_DEBUG(debug,"executing callback");
		result = data->getCallback()(data);
		pthread_cleanup_pop(1);
	} else {
		IBMRAS_DEBUG(debug,"stopMethod not present, executing callback");
		result = data->getCallback()(data);
	}
	return result;
}

uintptr_t createThread(ThreadData* data) {
	IBMRAS_DEBUG(fine,"in thread.cpp->createThread");
	uintptr_t retval;
	// lock the threadMap as we might be making updates to it
	pthread_mutex_lock(&threadMapMux);
	if (!stopping) {
		pthread_t thread;
		retval = pthread_create(&thread, NULL, wrapper, data);
		if (retval == 0) {
			IBMRAS_DEBUG(debug,"Thread created successfully");
			// only store valid threads
			threadMap.push(thread);
		}
	} else {
		IBMRAS_DEBUG(debug,"Trying to stop - thread not created");
		retval = ECANCELED;
	}
	pthread_mutex_unlock(&threadMapMux);
	return retval;
}

void exitThread(void *val) {
	IBMRAS_DEBUG(fine,"in thread.cpp->exitThread");
	pthread_exit(NULL);
}

void sleep(uint32 seconds) {
	IBMRAS_DEBUG(fine,"in thread.cpp->sleep");
	/* each sleep has its own mutex and condvar - the condvar will either
		be triggered by condBroadcast or it will timeout.*/
	pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
	pthread_cond_t c = PTHREAD_COND_INITIALIZER;

	IBMRAS_DEBUG(debug,"Updating condvar map");
	// lock the condvar map for update
	pthread_mutex_lock(&condMapMux);
	std::list<pthread_cond_t>::iterator it = condMap.insert(condMap.end(),c);
	pthread_mutex_unlock(&condMapMux);
	pthread_mutex_lock(&m);

	struct timespec t;
	clock_gettime(CLOCK_REALTIME, &t);
	t.tv_sec += seconds;		/* configure the sleep interval */
	IBMRAS_DEBUG_1(finest,"Sleeping for %d seconds", seconds);
	pthread_cond_timedwait(&c, &m, &t);
	IBMRAS_DEBUG(finest,"Woke up");
	pthread_mutex_unlock(&m);

	pthread_mutex_lock(&condMapMux);
	condMap.erase(it);
	pthread_mutex_unlock(&condMapMux);
}

void condBroadcast() {
	IBMRAS_DEBUG(fine,"in thread.cpp->condBroadcast");
	//prevent other threads adding to the condMap
	pthread_mutex_lock(&condMapMux);
	for (std::list<pthread_cond_t>::iterator it=condMap.begin(); it!=condMap.end(); ++it) {
		pthread_cond_broadcast(&(*it));
	}
	pthread_mutex_unlock(&condMapMux);
}

void stopAllThreads() {
	IBMRAS_DEBUG(fine,"in thread.cpp->stopAllThreads");
	//prevent new thread creation
	pthread_mutex_lock(&threadMapMux);
	stopping = true;
	// wake currently sleeping threads
	condBroadcast();
	while (!threadMap.empty()) {
    if (pthread_cancel(threadMap.top()) == -1 ) {
    	pthread_mutex_unlock(&threadMapMux);                                            
      perror("pthread_cancel failed");                                            
     } else {
		  //wait for the thread to stop
		  if (pthread_join(threadMap.top(), NULL) == -1 ) {
	      pthread_mutex_unlock(&threadMapMux);                                           
        perror("pthread_join failed"); 
      }
    }
		threadMap.pop();
	}
	pthread_mutex_unlock(&threadMapMux);
  stopping = false;
}

Semaphore::Semaphore(uint32 initial, uint32 max) {
	if (!stopping) {
		handle = new sem_t;
		IBMRAS_DEBUG(fine,"in thread.cpp creating CreateSemaphoreA");
		int result;
		result = sem_init(reinterpret_cast<sem_t*>(handle), 0, initial);
		if (result) {
			IBMRAS_DEBUG_1(warning, "Failed to create semaphore : error code %d", result);
			handle = NULL;
		}
	} else {
		IBMRAS_DEBUG(debug,"Trying to stop - semaphore not created");
		handle = NULL;
	}
}

void Semaphore::inc() {
	IBMRAS_DEBUG(finest, "Incrementing semaphore ticket count");
	if (handle) {
		sem_post(reinterpret_cast<sem_t*>(handle));
	}
}

bool Semaphore::wait(uint32 timeout) {
	int result;
	struct timespec t;
	while (!handle) {
		sleep(timeout);		/* wait for the semaphore to be established */
	}
	clock_gettime(CLOCK_REALTIME, &t);
	t.tv_sec++;		/* configure the sleep interval */
	IBMRAS_DEBUG(finest, "semaphore wait");
	result = sem_timedwait(reinterpret_cast<sem_t*>(handle), &t);
	if(!result) {
		IBMRAS_DEBUG(finest, "semaphore posted");
		return true;
	}

	IBMRAS_DEBUG(finest, "semaphore timeout");
	return (errno != ETIMEDOUT);
}

Semaphore::~Semaphore() {
	sem_destroy(reinterpret_cast<sem_t*>(handle));
	delete (sem_t*)handle;
}

}
}
}		/* end namespace port */
