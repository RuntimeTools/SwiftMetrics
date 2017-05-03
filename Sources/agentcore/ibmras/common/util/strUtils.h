 /**
 * IBM Confidential
 * OCO Source Materials
 * IBM Monitoring and Diagnostic Tools - Health Center
 * (C) Copyright IBM Corp. 2007, 2015 All Rights Reserved.
 * The source code for this program is not published or otherwise
 * divested of its trade secrets, irrespective of what has
 * been deposited with the U.S. Copyright Office.
 */


#include <string>
#include <vector>
#include "AgentExtensions.h"

#ifndef STRUTILS_H_
#define STRUTILS_H_

namespace ibmras {
namespace common {
namespace util {

std::vector<std::string> &split(const std::string &s, char delim, std::vector<std::string> &elems);
std::vector<std::string> split(const std::string &s, char delim);
bool endsWith(const std::string& str, const std::string& suffix);
bool startsWith(const std::string& str, const std::string& prefix);
DECL bool equalsIgnoreCase(const std::string& s1, const std::string& s2);
DECL void native2Ascii(char * str);
DECL void ascii2Native(char * str);
DECL void force2Native(char * str);
DECL char* createAsciiString(const char* nativeString);
DECL char* createNativeString(const char* asciiString);

}/*end of namespace util*/
}/*end of namespace common*/
} /*end of namespace ibmras*/




#endif /* STRUTILS_H_ */
