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

#ifndef ibmras_monitoring_bucketlist_h
#define ibmras_monitoring_bucketlist_h

#include "../../common/port/ThreadData.h"
#include "../../common/port/Lock.h"
#include "../connector/Connector.h"
#include "AgentExtensions.h"
#include "../Typesdef.h"
#include "Bucket.h"

namespace ibmras {
namespace monitoring {
namespace agent {


/* the list of all available buckets */
class DECL BucketList {
public:
	bool add(Bucket* bucket);					/* add a bucket to the list */
	bool add(std::vector<Bucket*> buckets);		/* add multiple buckets in one go */
	Bucket* findBucket(uint32 provID, uint32 sourceID);	/* find a bucket for a given provider */
	Bucket* findBucket(const std::string &uniqueID);
	void publish(ibmras::monitoring::connector::Connector &con); /* publish all bucket contents */
	void republish(const std::string &prefix, ibmras::monitoring::connector::Connector &con);
	bool addData(monitordata* data);
	std::vector<std::string> getIDs();
	std::string toString();						/* debug / log string version */
private:
	std::vector<Bucket*> buckets;				/* start of the list of buckets */
};
}
}
} /* end namespace agent */

#endif /* ibmras_monitoring_bucketlist_h */
