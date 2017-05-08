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


#ifndef ibmras_monitoring_agent_datasourcelist_h
#define ibmras_monitoring_agent_datasourcelist_h

#include "../../common/port/ThreadData.h"
#include "Bucket.h"
#include "../../common/common.h"
#include <sstream>

/*
 * Internal representation of data sources e.g. push or pull sources.
 * Because this is a template class, all of the definition needs to go in the
 * header file.
 */

namespace ibmras {
namespace monitoring {
namespace agent {

/*
 * Q : will data sources reference buckets, or will buckets reference data sources ?
 */
template <class T>
class DataSourceList {
public:
	void add(uint32 provID, T *src, std::string providerName);
	DataSourceList() {head = NULL; size = 0;}
	uint32 getSize();
	void clear();
	std::string toString();
	std::vector<Bucket*> getBuckets();
	DataSource<T>* getItem(uint32 index);
private:
	DataSource<T> *head;
	uint32 size;
};


/*
 * Add all push/pull sources from a particular provider to the master data source list
 */
template <class T>
void DataSourceList<T>::add(uint32 provID, T *src, std::string providerName) {
	DataSource<T> *dsrc = NULL;
	DataSource<T> *insertAt = NULL;
	while(src) {
		size++;
		dsrc = new DataSource<T>(provID, src, providerName);
		if(!insertAt) {
			if(head) {		/* items are already in the list */
				insertAt = head;
				while(insertAt->next) {
					insertAt = insertAt->next;
				}
			} else {
				head = dsrc;
				insertAt = head;	/* nothing in list at the moment so this is the new head */
				src = src->next;
				continue;
			}
		}
		insertAt->next = dsrc;
		insertAt = dsrc;
		src = src->next;
	}
}

template <class T>
uint32 DataSourceList<T>::getSize() {
	return size;
}

template <class T>
void DataSourceList<T>::clear() {
	head = NULL;
  size = 0;
}

template <class T>
std::string DataSourceList<T>::toString() {
	DataSource<T> *src = head;
	std::stringstream str;
	str << "Data source list : size = " << common::itoa(getSize()) << '\n';
	while(src) {
		str << src->toString();
		src = src->next;
	}
	return str.str();
}

template <class T>
std::vector<Bucket*> DataSourceList<T>::getBuckets() {
	std::vector<Bucket*> buckets;
	DataSource<T> *src = head;
	while(src) {
		Bucket* bucket = new Bucket(src->getProvID(), src->getSourceID(), src->getCapacity(),src->getUniqueID());
		buckets.push_back(bucket);
		src = src->next;
	}
	return buckets;
}


/* could improve this by remembering the last index/value as this is likely used from an iterator */
template <class T>
DataSource<T>* DataSourceList<T>::getItem(uint32 index) {
	uint32 count = 0;
	DataSource<T> *src = head;
	while(src && (count++ < index)) {
		src = src->next;
	}
	return src;
}


}
}
} /* end namespace agent */

#endif /* ibmras_monitoring_agent_datasourcelist_h */
