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

#include "BucketList.h"
#include "../../common/logging.h"
#include <sstream>

namespace ibmras {
namespace monitoring {
namespace agent {

namespace bucket {
extern IBMRAS_DECLARE_LOGGER;
}
using namespace bucket;





bool BucketList::add(Bucket* bucket) {
	IBMRAS_DEBUG(fine,  "BucketList::add(Bucket* bucket)  adding a bucket");
	buckets.push_back(bucket);
	return true;
}

std::string BucketList::toString() {
	std::stringstream str;
	str << "Bucket list : start\n";
	for (std::vector<Bucket*>::iterator i = buckets.begin(); i != buckets.end();
			++i) {
		str << (*i)->toString();
	}
	return str.str();
}

bool BucketList::add(std::vector<Bucket*> buckets) {
	IBMRAS_DEBUG(fine,
			"BucketList::add(std::vector<Bucket*> buckets)  adding a bucket");
	bool result = true;
	for (uint32 i = 0; i < buckets.size(); i++) {
		add(buckets[i]);
	}
	return result; /* cumulative result of all additions */
}

Bucket* BucketList::findBucket(uint32 provID, uint32 sourceID) {
	for (uint32 i = 0; i < buckets.size(); i++) {
		Bucket* b = buckets[i];
		if ((b->getProvID() == provID) && (b->getSourceID() == sourceID)) {
			return b; /* found a matching bucket */
		}
	}
	return NULL; /* did not find a matching bucket */
}

Bucket* BucketList::findBucket(const std::string &uniqueID) {
	for (uint32 i = 0; i < buckets.size(); i++) {
		Bucket* b = buckets[i];

		if (uniqueID.compare((b->getUniqueID())) == 0) {
			return b; /* found a matching bucket */
		}
	}
	return NULL; /* did not find a matching bucket */
}

void BucketList::publish(ibmras::monitoring::connector::Connector &con) {
	for (uint32 i = 0; i < buckets.size(); i++) {
		Bucket* b = buckets[i];
		b->publish(con);
	}
}

void BucketList::republish(const std::string &prefix, ibmras::monitoring::connector::Connector &con) {
	for (uint32 i = 0; i < buckets.size(); i++) {
		Bucket* b = buckets[i];
		b->republish(prefix, con);
	}
}

bool BucketList::addData(monitordata* data) {
	if (data != NULL && (data->size > 0 && data->data != NULL)) {
		Bucket* b = findBucket(data->provID, data->sourceID);
		if (b) {
			return b->add(data); /* found a matching bucket so add the data*/
		}

		IBMRAS_DEBUG_2(warning, "Attempted to add data to missing bucket [%d:%d]",
				data->provID, data->sourceID);
	}
	return false;
}

std::vector<std::string> BucketList::getIDs() {
	std::vector<std::string> ids;

	for (std::vector<Bucket*>::iterator i = buckets.begin(); i != buckets.end();
			++i) {
		ids.push_back(((*i)->getUniqueID()));
	}

	return ids;
}

}
}
} /* end namespace agent */
