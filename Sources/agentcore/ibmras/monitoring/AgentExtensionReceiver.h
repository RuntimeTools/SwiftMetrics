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


#ifndef AGENTEXTENSIONRECEIVER_H_
#define AGENTEXTENSIONRECEIVER_H_

#include "AgentExtensions.h"
#include "connector/Receiver.h"
#include "AgentExtensions.h"

namespace ibmras {
namespace monitoring {

class DECL AgentExtensionReceiver : public ibmras::monitoring::connector::Receiver {
public:
	AgentExtensionReceiver(RECEIVE_MESSAGE cb) : 
			receiveMessageCallback(cb) {
	}
	virtual ~AgentExtensionReceiver() {}
	void receiveMessage(const std::string &id, uint32 size, void *data) {
		if (receiveMessageCallback) {
			receiveMessageCallback(id.c_str(), size, data);
		}
	}
	
private:
	RECEIVE_MESSAGE receiveMessageCallback;
};
	
}
}

#endif /* AGENTEXTENSIONRECEIVER_H_ */