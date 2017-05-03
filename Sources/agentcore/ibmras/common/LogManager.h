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


#ifndef ibmras_common_logmanager_h
#define ibmras_common_logmanager_h

#include <iostream>
#include <string>
#include "AgentExtensions.h"
#include "../monitoring/Typesdef.h"
#include "Logger.h"
#include "port/Lock.h"

namespace ibmras {
	namespace common {

		typedef void* (*LOCAL_LOGGER_CALLBACK)(const std::string &msg); /* shortcut definition for the local log callback */

		/*
		 * Common logging functions
		 */
		class DECL LogManager {
		public:
			static LogManager* getInstance();

			loggingLevel level; /* will default to 0 which is 'none' in the log level enum */
			bool localLog; /* setting this to true will push all output to local stderr */
			static LOCAL_LOGGER_CALLBACK localLogFunc; /* optional function to invoke for local callbacks */
			static void msgHandler(const std::string &msg, loggingLevel level, Logger* logger); /* common message processing */

			static Logger* getLogger(const std::string &name); /* return instance of the logger */

			void setLevel(loggingLevel level); /* set the log level for all components */
			void setLevel(const std::string &name, const std::string &level);
			void setLevel(const std::string &name, loggingLevel level); /* set the log level for a named component logger */
		protected:
			LogManager();

		private:
			static LogManager* instance;
			std::vector<Logger*> loggers;
			ibmras::common::port::Lock* lock; /* lock to prevent spills whilst publishing/sending */

			void processMsg(const std::string& msg); /* common message processing */

			Logger* findLogger(const std::string &name); /* find a named logger */
		};
	}
}
#endif /* ibmras_common_logmanager_h */
