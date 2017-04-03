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


#ifndef ibmras_common_properties_h
#define ibmras_common_properties_h
#include "AgentExtensions.h"
#include <stdlib.h>
#include <istream>
#include <string>
#include <list>
#include <map>

namespace ibmras {
namespace common {

class DECL Properties {
public:
	virtual std::string get(const std::string &key, const std::string &defaultValue = "");
	virtual bool exists(const std::string &key);
	virtual void put(const std::string &key, const std::string &value);
	virtual void add(const Properties &p);
	virtual void add(const std::string &propString);
	virtual std::list<std::string> getKeys(const std::string& prefix = "");
	virtual std::string toString();

	virtual ~Properties() {}
protected:
	std::map<std::string, std::string> props;

};
/* end class Properties */
}
} /* end namespace RASCommon */

#endif /* ibmras_common_properties_h */
