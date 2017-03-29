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

#ifndef ibmras_common_data_json_json_h
#define ibmras_common_data_json_json_h

#include "../../port/ThreadData.h"
#include "../../common.h"

/*
 * Header file for working with JSON data builder
 */

/*
 * A stat used for JSON formatting of the data. It consists of a string representation
 * of a name value pair.
 *
 * This code has not yet been tested
 */

class JSONStat {
public:
	JSONStat(const char* name) { this->name = name; value = NULL; }
	void setValue(char* value) { this->value = value;}
	void setValue(double value) { this->value = ibmras::common::itoa(value); };
	const char* getName();
	char* getValue();
private:
	const char* name;
	char* value;
};

/*
 * The container for one or more data statistics
 */

class JSONStats {
public:
	JSONStats(uint32 max);
	const char* JSON();
	~JSONStats();
protected:
	JSONStat** stats;
    std::string* data;
    std::string* json;
    uint32 count;
    uint32 max;
};


#endif /* ibmras_common_data_json_json_h */
