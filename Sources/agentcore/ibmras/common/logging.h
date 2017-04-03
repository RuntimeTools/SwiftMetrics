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


#ifndef ibmras_common_logging_h
#define ibmras_common_logging_h

#include "LogManager.h"
extern "C" {
	void* ibmras_common_LogManager_getLogger(const char* name);
}

#define IBMRAS_DECLARE_LOGGER ibmras::common::Logger* logger;
#define IBMRAS_ASSIGN_LOGGER(name) {logger = (ibmras::common::Logger*)ibmras_common_LogManager_getLogger( name );}
#define IBMRAS_DEFINE_LOGGER(name) ibmras::common::Logger* logger = (ibmras::common::Logger*)ibmras_common_LogManager_getLogger( name );

/* Define logging macros */
#define IBMRAS_LOG(LOGLEVEL, MSG) {if (logger->level >= LOGLEVEL) { logger->log(LOGLEVEL, MSG);}}
#define IBMRAS_LOG_1(LOGLEVEL, MSG, INSERT1) {if (logger->level >= LOGLEVEL) { logger->log(LOGLEVEL, MSG, INSERT1);}}
#define IBMRAS_LOG_2(LOGLEVEL, MSG, INSERT1, INSERT2) {if (logger->level >= LOGLEVEL) { logger->log(LOGLEVEL, MSG, INSERT1, INSERT2);}}
#define IBMRAS_LOG_3(LOGLEVEL, MSG, INSERT1, INSERT2, INSERT3) {if (logger->level >= LOGLEVEL) { logger->log(LOGLEVEL, MSG, INSERT1, INSERT2, INSERT3);}}
#define IBMRAS_LOG_4(LOGLEVEL, MSG, INSERT1, INSERT2, INSERT3, INSERT4) {if (logger->level >= LOGLEVEL) { logger->log(LOGLEVEL, MSG, INSERT1, INSERT2, INSERT3, INSERT4);}}

/* Define debug logging macros */
#if defined(IBMRAS_DEBUG_LOGGING)
#define IBMRAS_DEBUG(LOGLEVEL, MSG) {if (logger->debugLevel >= LOGLEVEL) { logger->logDebug(LOGLEVEL, MSG);}}
#define IBMRAS_DEBUG_1(LOGLEVEL, MSG, INSERT1) {if (logger->debugLevel >= LOGLEVEL) { logger->logDebug(LOGLEVEL, MSG, INSERT1);}}
#define IBMRAS_DEBUG_2(LOGLEVEL, MSG, INSERT1, INSERT2) {if (logger->debugLevel >= LOGLEVEL) { logger->logDebug(LOGLEVEL, MSG, INSERT1, INSERT2);}}
#define IBMRAS_DEBUG_3(LOGLEVEL, MSG, INSERT1, INSERT2, INSERT3) {if (logger->debugLevel >= LOGLEVEL) { logger->logDebug(LOGLEVEL, MSG, INSERT1, INSERT2, INSERT3);}}
#define IBMRAS_DEBUG_4(LOGLEVEL, MSG, INSERT1, INSERT2, INSERT3, INSERT4) {if (logger->debugLevel >= LOGLEVEL) { logger->logDebug(LOGLEVEL, MSG, INSERT1, INSERT2, INSERT3, INSERT4);}}
#else
#define IBMRAS_DEBUG(LOGLEVEL, MSG)
#define IBMRAS_DEBUG_1(LOGLEVEL, MSG, INSERT1)
#define IBMRAS_DEBUG_2(LOGLEVEL, MSG, INSERT1, INSERT2)
#define IBMRAS_DEBUG_3(LOGLEVEL, MSG, INSERT1, INSERT2, INSERT3)
#define IBMRAS_DEBUG_4(LOGLEVEL, MSG, INSERT1, INSERT2, INSERT3, INSERT4)

#endif /* IBMRAS_DEBUG_LOGGING */

#endif /* ibmras_common_logging_h */
