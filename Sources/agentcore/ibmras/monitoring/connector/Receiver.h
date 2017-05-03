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


#ifndef ibmras_monitoring_connector_receiver_h
#define ibmras_monitoring_connector_receiver_h

#include <string>
#include "../../common/types.h"

namespace ibmras{
namespace monitoring {
namespace connector {

class Receiver {
public:
	virtual void receiveMessage(const std::string &id, uint32 size,
			void *data) = 0;

	virtual ~Receiver() {
	}

protected:
	Receiver() {
	}
};

}
}
} /* namespace connector */
#endif /* ibmras_monitoring_connector_receiver_h */
