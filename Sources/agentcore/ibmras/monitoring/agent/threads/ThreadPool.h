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


#ifndef ibmras_monitoring_agent__threads_threadpool_h
#define ibmras_monitoring_agent__threads_threadpool_h

#include "../../../common/port/ThreadData.h"
#include "../../../common/port/Semaphore.h"
#include "AgentExtensions.h"
#include "../../Typesdef.h"
#include "WorkerThread.h"

namespace ibmras {
namespace monitoring {
namespace agent {
namespace threads {

/* a pool of worker threads */
class ThreadPool {
public:
	ThreadPool();
	void addPullSource(pullsource* src);

	void startAll();			/* start all threads in this pool */
	void stopAll();				/* stop all threads in this pool */

	void process(bool immediate);				/* process queue entries */
	~ThreadPool();
private:
	std::vector<WorkerThread*> threads;			/* worker threads */
	bool stopping;								/* flag to prevent adding pull sources during stop */
};

}
}
}
}	/* end namespace threads */

#endif /* ibmras_monitoring_agent__threads_threadpool_h */
