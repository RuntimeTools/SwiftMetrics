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


#include "PropertiesFile.h"

#include <fstream>
#include <string>
#include <cctype>
#include <algorithm>

namespace ibmras {
namespace common {

bool IsWhitespace(char x) { return std::isspace(x); }

int PropertiesFile::load(const std::string &inputFile) {
	std::ifstream in_file(inputFile.c_str());
	if (in_file.fail()) {
		return -1;
	}
	std::string line;
	while(std::getline(in_file, line)) {
		if (line.find('#') == 0) {
			continue;
		}
		// trim line ending
		if (line.length() > 0 && line.at(line.length() - 1) == '\r') {
			line.erase(line.length() - 1);
		}
		// erase whitespace
				line.erase(std::remove_if(line.begin(),
				                          line.end(),
				                          IsWhitespace),
				               line.end());
		size_t pos = line.find('=');
		if ((pos != std::string::npos) && (pos < line.size())) {
			put(line.substr(0, pos), line.substr(pos + 1));
		}
	}

	return 0;
}


}
} /* end namespace monitoring */


