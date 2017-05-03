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


#ifndef SYSTEMRECEIVER_H_
#define SYSTEMRECEIVER_H_

#include "../connector/Receiver.h"
#include "../Plugin.h"
#include "AgentExtensions.h"

extern "C" DECL void* ibmras_getSystemReceiver();


namespace ibmras{
namespace monitoring {
namespace agent {

extern "C" DECL const char* getVersionSys();

class SystemReceiver: public ibmras::monitoring::connector::Receiver, public ibmras::monitoring::Plugin {
public:
	SystemReceiver();
	virtual ~SystemReceiver();
	int startReceiver();
	int stopReceiver();
	void receiveMessage(const std::string &id, uint32 size, void *data);
};
}
}
} /* namespace monitoring */
#endif /* SYSTEMRECEIVER_H_ */
