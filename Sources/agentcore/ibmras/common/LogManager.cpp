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


#include <iostream>
#include <cstdarg>
#include <cstdio>
#include <string>

#include "LogManager.h"


#if defined(_WINDOWS)
#define VPRINT vsprintf_s
#else
#define VPRINT vsprintf
#endif

extern "C" {

DECL void* ibmras_common_LogManager_getLogger(const char* name) {
	return (void*) ibmras::common::LogManager::getLogger(name);
}
}

namespace ibmras {
namespace common {

LogManager* LogManager::instance = NULL;

LOCAL_LOGGER_CALLBACK LogManager::localLogFunc = NULL;

LogManager::LogManager() :
		level(info), localLog(true), lock(NULL) {
	/* do not create a lock in the constructor as it will create a loop with the logging in the port library */
}


void LogManager::processMsg(const std::string &msg) {

	if (localLog) {
		/* local logging is overriding */
		if (localLogFunc) {
			localLogFunc(msg);
		} else {
			std::cerr << msg << '\n';
			std::cerr.flush();
		}
		return;
	}

}

void LogManager::msgHandler(const std::string &message, loggingLevel level,
		Logger* logger) {

	/* logger level has priority over log manager level (which should be considered a default level */
	if ((logger->level >= level) || (instance->level >= level)) {
		instance->processMsg(message);
	}
}

void LogManager::setLevel(loggingLevel newlevel) {
	LogManager::level = newlevel;
	for (std::vector<Logger*>::iterator i = loggers.begin(); i != loggers.end();
			++i) {
		if ((*i)->level <= level) {
			(*i)->level = level;
		}
	}
}

void LogManager::setLevel(const std::string &name, loggingLevel newlevel) {
	if (name.compare("level") == 0) {
		setLevel(newlevel);
	} else {
		Logger* logger = getLogger(name);
		if (level > newlevel) {
			logger->level = level;
		} else {
			logger->level = newlevel;
		}
		logger->debugLevel = newlevel;
	}
}

LogManager* LogManager::getInstance() {
	if (!instance) {
		instance = new LogManager;
		instance->lock = new ibmras::common::port::Lock;
	}
	return instance;
}

Logger* LogManager::getLogger(const std::string &name) {
	LogManager* instance = getInstance();
	Logger* logger = instance->findLogger(name);
	if (!logger) { /* logger not found so need to create a new instance and return that */
		logger = new Logger(name, LogManager::msgHandler);
		instance->loggers.push_back(logger);
	}

	return logger;
}

void LogManager::setLevel(const std::string& name, const std::string& value) {
	loggingLevel lev = none;
	if (value.compare("warning") == 0) {
		lev = warning;
	} else if (value.compare("info") == 0) {
		lev = info;
	} else if (value.compare("fine") == 0) {
		lev = fine;
	} else if (value.compare("finest") == 0) {
		lev = finest;
	} else if (value.compare("debug") == 0) {
		lev = debug;
	} else {
		lev = none;
	}
	setLevel(name, lev);
}

Logger* LogManager::findLogger(const std::string &name) {

	for (std::vector<Logger*>::iterator i = loggers.begin(); i != loggers.end();
			++i) {
		if ((*i)->component == name) {
			return (*i);
		}
	}
	return NULL; /* no match found */
}


}
}
