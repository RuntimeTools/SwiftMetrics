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
#define _XOPEN_SOURCE_EXTENDED 1
#include "pthread.h"
#include <time.h>
#include <sys/time.h>
#include <errno.h>
#include <mach/clock.h>
#include <mach/mach.h>
#include <mach/task.h>
#include <fcntl.h>           /* For O_* constants */
#include <sys/stat.h>        /* For mode constants */
#include <semaphore.h>
#include <sys/types.h>
#include <unistd.h>


#include "../ThreadData.h"
#include "../Semaphore.h"
#include "../../logging.h"
#include "../../common.h"
#include "../../util/sysUtils.h"
#include <map>
#include <stack>
#include <list>

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

	struct timeval tv;
    struct timespec ts;
    gettimeofday(&tv, NULL);
    ts.tv_sec = tv.tv_sec + seconds;
    ts.tv_nsec = 0;
	IBMRAS_DEBUG_1(finest,"Sleeping for %d seconds", seconds);
	pthread_cond_timedwait(&c, &m, &ts);
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
        name = "/hc/";
        name.append(ibmras::common::itoa(getpid()));
        name.append("/");
        name.append(ibmras::common::itoa(pthread_self()));
		handle = new sem_t;
		IBMRAS_DEBUG_1(fine, "in thread.cpp creating semaphore %s", name.c_str());

		handle = sem_open(name.c_str(), O_CREAT | O_EXCL, S_IRWXU | S_IRWXG | S_IRWXO, initial);
        int i=0;
		if (handle == SEM_FAILED) {
            while (i<=20) {
                std::string i_string = ibmras::common::itoa(i);
                name.replace(name.length()-i_string.length(), i_string.length(), i_string);
                IBMRAS_DEBUG_1(fine, "Failed; creating semaphore %s", name.c_str());
                handle = sem_open(name.c_str(), O_CREAT | O_EXCL, S_IRWXU | S_IRWXG | S_IRWXO, initial);
                if (handle == SEM_FAILED) {
                    i++;
                } else {
                    return;
                }
            }
			IBMRAS_DEBUG(warning, "Failed to create semaphore : error code SEM_FAILED\n");
			handle = NULL;
		}
	} else {
		IBMRAS_DEBUG(debug,"Trying to stop - semaphore not created");
		handle = NULL;
	}
}

void Semaphore::inc() {
	IBMRAS_DEBUG_1(finest, "Incrementing semaphore %s ticket count\n", name.c_str());
	if (handle) {
		sem_post(reinterpret_cast<sem_t*>(handle));
	}
}

bool Semaphore::wait(uint32 timeout) {
	int result;
	while (!handle) {
		sleep(timeout);		/* wait for the semaphore to be established */
	}
	IBMRAS_DEBUG_1(finest, "semaphore %s wait\n", name.c_str());

    //best can do here as OSX doesn't do sem_timedwait; trywait returns immediately
    //and we can check the result to see if we need to sleep and try again.

	result = sem_trywait(reinterpret_cast<sem_t*>(handle));
    if (result == -1 && errno == EAGAIN) {
        ibmras::common::port::sleep(timeout);
        result = sem_trywait(reinterpret_cast<sem_t*>(handle)); 
    }

	if(!result) {
		IBMRAS_DEBUG_1(finest, "semaphore %s posted\n", name.c_str());
		return true;
	}

	IBMRAS_DEBUG_1(finest, "possible semaphore %s timeout\n", name.c_str());
	return (errno != EAGAIN);
}

Semaphore::~Semaphore() {
    sem_close(reinterpret_cast<sem_t*>(handle));
    sem_unlink(name.c_str());
}

}
}
}		/* end namespace port */
