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


#ifndef ibmras_monitoring_agent_threads_workerthread_h
#define ibmras_monitoring_agent_threads_workerthread_h

#include "../../../common/port/ThreadData.h"
#include "../../../common/port/Semaphore.h"
#include "AgentExtensions.h"
#include "../../Typesdef.h"

namespace ibmras {
namespace monitoring {
namespace agent {
namespace threads {

class WorkerThread {
public:
	WorkerThread(pullsource* source);
	void start();				/* start this worker thread taking from the queue */
	void stop();				/* stop this thread from taking any more entries */

	void process(bool immediate);
	bool isStopped();

	static void* threadEntry(ibmras::common::port::ThreadData* data);
	static void* cleanUp(ibmras::common::port::ThreadData* data);
private:
	void* processLoop();
	bool running;
	bool stopped;
	ibmras::common::port::Semaphore semaphore;		/* sempahore to control data processing */
	pullsource* source;		/* source to pull data from */
	ibmras::common::port::ThreadData data;
	int countdown;
};

}
}
}
}	/* end namespace threads */

#endif /* ibmras_monitoring_agent_threads_workerthread_h */
