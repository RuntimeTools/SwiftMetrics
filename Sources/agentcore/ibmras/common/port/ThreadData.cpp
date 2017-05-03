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
 * Implementation of common port library classes
 */

#include "ThreadData.h"


namespace ibmras {

namespace common {

namespace port {


ThreadData::ThreadData(THREAD_CALLBACK callback) {
	this->callback = callback;
	handle = (static_cast<unsigned int>(NULL));
	args = NULL;
	hasstopmethod = false;
}


ThreadData::ThreadData(THREAD_CALLBACK callback, THREAD_CALLBACK stopMethod) {
	this->callback = callback;
	this->stopmethod = stopMethod;
	handle = (static_cast<unsigned int>(NULL));
	args = NULL;
	hasstopmethod = true;
}

void ThreadData::setArgs(void* args) {
	this->args = args;
}

void* ThreadData::getArgs() {
	return args;
}

THREAD_CALLBACK ThreadData::getCallback() {
	return callback;
}

THREAD_CALLBACK ThreadData::getStopMethod() {
	return stopmethod;
}

bool ThreadData::hasStopMethod() {
	return hasstopmethod;
}

}
}
} /* end of namespace port */
