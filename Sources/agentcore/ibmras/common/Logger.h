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


#ifndef ibmras_common_logger_h
#define ibmras_common_logger_h

#include "AgentExtensions.h"
#include "../monitoring/Typesdef.h"

#include <string>

namespace ibmras {
namespace common {

class DECL Logger;

typedef void (*MSG_HANDLER)(const std::string &msg, loggingLevel Level, Logger* logger); /* common message processing */

class DECL Logger {
public:
	Logger(const std::string &name, MSG_HANDLER h);
	virtual ~Logger();

	void log(loggingLevel lev, const char* format, ...); /* variable number of parameters should be string messages */
	void logDebug(loggingLevel lev, const char* format, ...); /* variable number of parameters should be string messages */

	loggingLevel level; /* level that the logger is operating at */
	loggingLevel debugLevel; /* level that the logger is operating at */
	std::string component;

private:
	MSG_HANDLER handler;

	void header(std::stringstream &str, loggingLevel lev, bool debug=false);
};

} /* namespace common */
} /* namespace ibmras */
#endif /* ibmras_common_logger_h */
