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


#if defined (_ZOS)
#define _ISOC99_SOURCE
#endif
#include <iostream>
#include <cstdarg>
#include <cstdio>
#include <string>
#include <sstream>

#include <ctime>

#include "Logger.h"

#if defined(_WINDOWS)
#define VPRINT vsnprintf_s
#else
#define VPRINT vsnprintf
#endif
#if defined(_ZOS)
#include <unistd.h>
#endif

namespace ibmras {
namespace common {

Logger::Logger(const std::string &name, MSG_HANDLER h) :
		level(none), debugLevel(none), component(name), handler(h) {
}

Logger::~Logger() {
}

void Logger::header(std::stringstream &str, loggingLevel lev, bool dbg) {
	std::time_t time = std::time(NULL);
	char buffer[100];

	if (std::strftime(buffer, sizeof(buffer), "%c", std::localtime(&time))) {
		str << '[' << buffer << ']';
	}
	str << " com.ibm.diagnostics.healthcenter." << component;

	if (dbg) {
		str << ".debug";
	}

	switch (lev) {
	case info:
		str << " INFO: ";
		break;
	case warning:
		str << " WARNING: ";
		break;
	case fine:
		str << " FINE: ";
		break;
	case finest:
		str << " FINEST: ";
		break;
	case debug:
		str << " DEBUG: ";
		break;
	default:
		str << " ";
		break;
	}
}

void Logger::log(loggingLevel lev, const char* format, ...) {
	std::stringstream str;
	header(str, lev);
	va_list messages;
	va_start(messages, format);
	char buffer[1024];
	int result = VPRINT(buffer, 1024, format, messages);
	va_end(messages);
	if (result >= 0) {
		str << buffer;
	} else {
		str << "(warning) failed to write replacements for :" << format;
	}
	std::string msg = str.str();
	handler(msg.c_str(), lev, this);

}

void Logger::logDebug(loggingLevel lev, const char* format, ...) {
	std::stringstream str;
	header(str, lev, true);
	va_list messages;
	va_start(messages, format);
	char buffer[1024];
	int result = VPRINT(buffer, 1024, format, messages);
	va_end(messages);
	if (result >= 0) {
		str << buffer;
	} else {
		str << "(warning) failed to write replacements for :" << format;
	}
	std::string msg = str.str();
	handler(msg.c_str(), lev, this);
}

}

}
