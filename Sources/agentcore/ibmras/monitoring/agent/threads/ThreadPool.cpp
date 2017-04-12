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
 * Thread pool and associated worker threads
 */

#include "ThreadPool.h"
#include "../Agent.h"
#include "../../../common/logging.h"

namespace ibmras {
namespace monitoring {
namespace agent {
namespace threads {

IBMRAS_DEFINE_LOGGER("Threads")
;

ThreadPool::ThreadPool() {
	stopping = false;
}

void ThreadPool::addPullSource(pullsource* src) {
	if (!stopping) {
		threads.push_back(new WorkerThread(src));
	}
}

void ThreadPool::startAll() {
	IBMRAS_DEBUG(info, "Starting thread pool");
	stopping = false;
	for (uint32 i = 0; i < threads.size(); i++) {
		threads[i]->start();
	}
}

void ThreadPool::stopAll() {
	IBMRAS_DEBUG(info, "Stopping thread pool");
	//prevent any new pull sources being added
	stopping = true;
	for (uint32 i = 0; i < threads.size(); i++) {
		threads[i]->stop();
	}
	uint32 stoppedCount = 0;
	uint32 maxWait = 5;
	while ((stoppedCount < threads.size()) && (maxWait > 0)) {
		stoppedCount = 0;
		for (uint32 i = 0; i < threads.size(); i++) {
			if (threads[i]->isStopped()) {
				stoppedCount++;
			}
		}

		if (stoppedCount == threads.size()) {
			break;
		}

		IBMRAS_DEBUG_1(debug, "Waiting for %d worker threads to stop", threads.size() - stoppedCount);
		ibmras::common::port::sleep(1);
		maxWait--;
	}
}

ThreadPool::~ThreadPool() {
	stopping = true;
	for (uint32 i = 0; i < threads.size(); i++) {
		// Only delete threads that are stopped
		// unlikely leak but prevents an abort
		if (threads[i]->isStopped()) {
			delete threads[i];
		}
	}
}

void ThreadPool::process(bool immediate) {
	IBMRAS_DEBUG(finest, "Processing pull sources");
	for (uint32 i = 0; i < threads.size(); i++) {
		threads[i]->process(immediate);
	}
}

}
}
}
} /* end of namespace threads */

