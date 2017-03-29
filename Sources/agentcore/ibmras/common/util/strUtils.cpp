 /**
 * IBM Confidential
 * OCO Source Materials
 * IBM Monitoring and Diagnostic Tools - Health Center
 * (C) Copyright IBM Corp. 2007, 2015 All Rights Reserved.
 * The source code for this program is not published or otherwise
 * divested of its trade secrets, irrespective of what has
 * been deposited with the U.S. Copyright Office.
 */


#include "strUtils.h"
#include "../MemoryManager.h"
#include <sstream>
#include "../Logger.h"
#include <cstring>
#include <stdlib.h>
#include <string>
#include <stdint.h>


#if defined(WINDOWS)
#include <windows.h>
#include <intrin.h>
#include <winbase.h>
#endif

#if defined(_ZOS)
#include <unistd.h>
#endif

namespace ibmras {
namespace common {
namespace util {

std::vector<std::string> &split(const std::string &s, char delim, std::vector<std::string> &elems) {
    std::stringstream ss(s);
    std::string item;
    while (std::getline(ss, item, delim)) {
        elems.push_back(item);
    }
    return elems;
}

std::vector<std::string> split(const std::string &s, char delim) {
    std::vector<std::string> elems;
    split(s, delim, elems);
    return elems;
}

bool endsWith(const std::string& str, const std::string& suffix) {
	return (str.length() >= suffix.length() && (0 == str.compare(str.length() - suffix.length(), suffix.length(), suffix)));
}

bool startsWith(const std::string& str, const std::string& prefix) {
	return (str.length() >= prefix.length() && (0 == str.compare(0, prefix.length(), prefix)));
}


bool equalsIgnoreCase(const std::string& s1, const std::string& s2) {


	if (s1.length() != s2.length()) {
		return false;
	}

	for(std::string::size_type i = 0; i < s1.size(); ++i) {
	    if (toupper(s1[i]) !=  toupper(s2[i]) ) {
	    	return false;
	    }
	}

	return true;
}


void native2Ascii(char * str) {
#if defined(_ZOS)
    if ( NULL != str )
    {
        __etoa(str);
    }
#endif
}


/******************************/
void
ascii2Native(char * str)
{
#if defined(_ZOS)
    if ( NULL != str )
    {
        __atoe(str);
    }
#endif

}


/******************************/
void
force2Native(char * str)
{
#ifdef _ZOS
	char *p = str;

    if ( NULL != str )
    {
        while ( 0 != *p )
        {
            if ( 0 != ( 0x80 & *p ) )
            {
                p = NULL;
                break;
            }
            p++;
        }

        if ( NULL != p )
        {
            __atoe(str);
        }
    }
#endif
}

char* createAsciiString(const char* nativeString) {
    char* cp = NULL;
    if ( NULL != nativeString )
    {
        cp = (char*)ibmras::common::memory::allocate(strlen(nativeString) + 1);
        if ( NULL == cp )
        {
            return NULL;
        } else
        {
            /* jnm is valid, so is cp */
            strcpy(cp,nativeString);
            native2Ascii(cp);
        }
    }
    return cp;
}

char* createNativeString(const char* asciiString) {
    char* cp = NULL;
    if ( NULL != asciiString )
    {
        cp = (char*)ibmras::common::memory::allocate(strlen(asciiString) + 1);
        if ( NULL == cp )
        {
            return NULL;
        } else
        {
            /* jnm is valid, so is cp */
            strcpy(cp,asciiString);
            ascii2Native(cp);
        }
    }
    return cp;
}


}/*end of namespace util*/
}/*end of namespace common*/
} /*end of namespace ibmras*/
