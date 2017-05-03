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

#ifndef ibmras_monitoring_bucket_h
#define ibmras_monitoring_bucket_h

#include "../../common/port/ThreadData.h"
#include "../../common/port/Lock.h"
#include "../connector/Connector.h"
#include "AgentExtensions.h"
#include "../Typesdef.h"

namespace ibmras {
namespace monitoring {
namespace agent {

/* a bucket holds a set of monitor data */
class DECL Bucket {

public:
	Bucket(uint32 provID, uint32 sourceID, uint32 capacity, const std::string& uniqueID);
	bool add(monitordata* entry);			/* adds monitor data to the bucket */
	std::string toString();			/* debug / log string version */
	uint32 getProvID();
	uint32 getSourceID();
	std::string getUniqueID();
	void publish(ibmras::monitoring::connector::Connector &con);				/* publish bucket contents to the connector manager */
	uint32 getNextData(uint32 id, int32 &size,	void* *data, uint32 &droppedCount);
	uint32 getNextPersistentData(uint32 id, uint32 &size, void* *data);
	void republish(const std::string &topicPrefix, ibmras::monitoring::connector::Connector &con);
private:
	bool spill(uint32 size);	/* spill bucket contents until there is the requested space */

	/* bucket data builds on the monitor data to add control meta-data. It also removes any
	 * unnecessary or repeated data elements
	 */
	class BucketData {
	public:
		BucketData(monitordata* mdata);
		virtual ~BucketData();
		uint32 id;				/* used by clients to request ranges of data */
		bool persistentData;
		uint32 size;				/* amount of data being provided */
		unsigned char *data;	/* char array of the data to store */
		BucketData* next;		/* next item in the bucket or null if this is the last item */
	};

	uint32 provID;
	uint32 sourceID;
	std::string uniqueID;  /*Name of the uniqueID plugin providing the name */
	BucketData* head;		/* when a bucket over flows then items are removed from the head */
	BucketData* tail;		/* when items are added to the bucket they are added to the tail */
	uint32 lastPublish;/* the last entry published */
	uint32 capacity;		/* maximum capacity for the bucket in bytes */
	uint32 publishSize; /* max data to send */
	uint32 size;			/* current size of the bucket */
	uint32 count;			/* number of items in the bucket */
	uint32 masterID;		/* master ID for items placed in the bucket */
	ibmras::common::port::Lock* lock;		/* lock to prevent spills whilst publishing/sending */

};


}
}
} /* end namespace agent */

#endif /* ibmras_monitoring_bucket_h */
