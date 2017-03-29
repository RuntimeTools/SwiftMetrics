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

#include "Bucket.h"
#include "../../common/common.h"
#include "../../common/logging.h"
#include "../../common/MemoryManager.h"
#include <sstream>
#include <string.h>

namespace ibmras {
namespace monitoring {
namespace agent {
namespace bucket {
IBMRAS_DEFINE_LOGGER("Bucket")
;
}
using namespace bucket;

Bucket::Bucket(uint32 provID, uint32 sourceID, uint32 capacity,
		const std::string &uniqueID) {
	this->provID = provID;
	this->sourceID = sourceID;
	this->capacity = capacity;
	publishSize = 1024 * 1024;
	this->uniqueID = uniqueID;
	count = 0;
	size = 0;
	head = NULL;
	tail = NULL;
	masterID = 0;
	lock = new ibmras::common::port::Lock;
	lastPublish = 0;
	IBMRAS_DEBUG_4(fine, "Bucket created for: %s, provider id: %d, source id: %d, capacity: %d", uniqueID.c_str(), provID, sourceID, capacity);
}

Bucket::BucketData::BucketData(monitordata* mdata) :
		id(0), persistentData(mdata->persistent), size(0), data(NULL), next(
				NULL) {
	if (mdata->size > 0 && mdata->data != NULL) {
		this->size = mdata->size;
		data = ibmras::common::memory::allocate(size);
		if (data != NULL) {
			memcpy(this->data, mdata->data, size);
		}
	}
}

Bucket::BucketData::~BucketData() {
	if (data) {
		ibmras::common::memory::deallocate(&data);
	}
}

void Bucket::publish(ibmras::monitoring::connector::Connector &con) {
	if (!lock->acquire()) {
		if (!lock->isDestroyed()) {

			uint32 maxSendSize = size;
			if (maxSendSize > publishSize) {
				maxSendSize = publishSize;
			}

			unsigned char* dataToSend = ibmras::common::memory::allocate(
					maxSendSize);
			uint32 sizeToSend = 0;

			uint32 lastidsent = lastPublish;
			BucketData* current = head;
			while (current) {
				if ((current->id > lastPublish) || !lastPublish) {
					if ((sizeToSend > 0)
							&& ((sizeToSend + current->size) > maxSendSize)) {
						// We have a batch and the next will not fit in the buffer so send it
						IBMRAS_DEBUG_2(fine, "publishing batched message to %s of %d bytes",
								uniqueID.c_str(), sizeToSend);
						con.sendMessage(uniqueID, sizeToSend, dataToSend);
						sizeToSend = 0;
					}

					if (dataToSend
							&& ((sizeToSend + current->size) <= maxSendSize)) {
						// We are batching the messages and this will fit in the buffer
						// Batch the message in the buffer
						memcpy(dataToSend + sizeToSend, current->data,
								current->size);
						sizeToSend += current->size;

					} else {
						// Publish from bucket
						IBMRAS_DEBUG_2(fine, "publishing message to %s of %d bytes",
								uniqueID.c_str(), current->size);
						con.sendMessage(uniqueID, current->size, current->data);
					}
					lastidsent = current->id;
				}
				current = current->next;
			}
			// Publish any remaining batched data
			if (dataToSend && (sizeToSend > 0)) {
				IBMRAS_DEBUG_2(fine, "publishing batched message to %s of %d bytes",
						uniqueID.c_str(), sizeToSend);
				con.sendMessage(uniqueID, sizeToSend, dataToSend);
			}
			lastPublish = lastidsent;
			ibmras::common::memory::deallocate(&dataToSend);

			lock->release();
		}
	}
}

bool Bucket::spill(uint32 entrysize) {

	BucketData* bdata; /* used to manage the bucket data */
	uint32 i = 0;

	BucketData *cursor = head;
	BucketData *prev = NULL;
	while (((size + entrysize) > capacity) && (cursor != NULL)
			&& (cursor->id <= lastPublish)) {
		if (!cursor->persistentData) {
			bdata = cursor;
			size -= bdata->size;
			count--;
			i++;
			if (prev == NULL) {
				head = bdata->next;
			} else {
				prev->next = bdata->next;
			}
			cursor = cursor->next;
			delete bdata;
		} else {
			prev = cursor;
			cursor = prev->next;
		}
	}
	if (!head) {
		tail = NULL; /* emptied the queue so there is no tail now either */
	}

	if (head && ((size + entrysize) > capacity)) {
		// No room within capacity
		return false;
	}

	IBMRAS_DEBUG_1(debug, "Removed %d entries from the bucket", i);

	IBMRAS_DEBUG_4(debug, "Bucket stats [%d:%d] : count = %d, size = %d", provID,
			sourceID, count, size);

	return true;

}

bool Bucket::add(monitordata* data) {

	if ((data->provID != provID) || (data->sourceID != sourceID)) {
		IBMRAS_DEBUG_4(info,
				"Wrong data sent to bucket : received %d:%d, expected %d, %d",
				data->provID, data->sourceID, provID, sourceID);
		return false; /* data not added as provider and source IDs do not match */
	}
	bool added = false;

	if (!lock->acquire()) {
		if (!lock->isDestroyed()) {
			if (spill(data->size)) {
				BucketData* bdata = new BucketData(data);
				if (bdata->data == NULL) {
					IBMRAS_DEBUG_2(warning, "Unable to allocate memory for %s data of size %d", uniqueID.c_str(), bdata->size);
					delete bdata;
				} else {
					bdata->id = ++masterID;

					if (tail) {
						tail->next = bdata; /* add new entry to tail */
						tail = bdata; /* make a new tail */
					} else {
						head = bdata;
						tail = bdata;
					}
					count++;
					size += data->size;
					added = true;
				}
			} else {
				IBMRAS_DEBUG_2(warning, "No room in bucket %s for data of size %d", uniqueID.c_str(), data->size);
			}
			lock->release();
		}
	}

	IBMRAS_DEBUG_4(debug,
			"Bucket data [%s] : data size = %d, bucket size = %d, count = %d",
			uniqueID.c_str(), data->size, size, count);
	return added; /* data added to bucket */
}

uint32 Bucket::getNextData(uint32 id, int32 &dataSize, void* *data,
		uint32 &droppedCount) {
	uint32 returnId = id;
	droppedCount = 0;
	*data = NULL;
	if (!lock->acquire()) {
		if (!lock->isDestroyed()) {
			uint32 requestedSize = dataSize;
			dataSize = 0;

			BucketData* current = head;
			while (current) {
				if (current->id > id) {
					droppedCount = current->id - (id + 1);

					// Calculate size to return
					BucketData* dataToSend = current;
					uint32 bufferSize = 0;
					if (requestedSize == 0) {
						bufferSize = current->size;
					} else {

						while (dataToSend) {
							bufferSize += dataToSend->size;
							if (requestedSize > 0
									&& bufferSize > requestedSize) {
								break;
							}
							if (dataToSend->next) {
								droppedCount += (dataToSend->next->id
										- (dataToSend->id + 1));
							}
							dataToSend = dataToSend->next;
						}

					}
					// Allocate buffer
					unsigned char* buffer = ibmras::common::memory::allocate(
							bufferSize);

					if (buffer == NULL) {
						IBMRAS_DEBUG_1(warning, "Unable to allocate buffer of %d", bufferSize);
						break;
					}
					dataToSend = current;
					while (dataToSend) {
						if ((dataToSend->size + dataSize) > bufferSize) {
							break;

						}
						// copy data to buffer
						unsigned char* dataPtr = dataToSend->data;
						memcpy(buffer + dataSize, dataPtr, dataToSend->size);
						dataSize += dataToSend->size;
						returnId = dataToSend->id;
						dataToSend = dataToSend->next;
					}
					*data = buffer;

					break;
				}
				current = current->next;
			}
			lock->release();
		}
	}

	return returnId;
}

/*
 * NOTE This method has NO locking as it is intended to be called by the thread that
 * already owns the bucket lock, ie from connectors called by the publish method
 *
 * NOTE as the caller has the lock we trust them with the data pointer rather than a copy
 */
uint32 Bucket::getNextPersistentData(uint32 id, uint32& dataSize, void** data) {
	uint32 returnId = id;

	IBMRAS_DEBUG(debug, "in Bucket::getNextPersistentData()");

	IBMRAS_DEBUG(debug, "in Bucket::getNextPersistentData() lock acquired");
	dataSize = 0;
	*data = NULL;

	BucketData* current = head;
	while (current && current->id <= lastPublish) {
		if (current->id > id && current->persistentData) {
			IBMRAS_DEBUG_1(debug, "in Bucket::getNextPersistentData() persistent entry found id", current->id);
			// Allocate buffer
			dataSize = current->size;
			*data = current->data;
			returnId = current->id;
			break;
		}
		current = current->next;
	}

	return returnId;
}

void Bucket::republish(const std::string &topicPrefix,
		ibmras::monitoring::connector::Connector &con) {
	IBMRAS_DEBUG_1(debug, "in Bucket::republish for %s", uniqueID.c_str());
	if (!lock->acquire()) {
		if (!lock->isDestroyed()) {

			uint32 maxSendSize = size;
			if (maxSendSize > publishSize) {
				maxSendSize = publishSize;
			}

			unsigned char* dataToSend = ibmras::common::memory::allocate(
					maxSendSize);
			uint32 sizeToSend = 0;

			std::string messageTopic = topicPrefix + uniqueID;

			BucketData* current = head;
			while (current && (current->id <= lastPublish)) {

				if ((sizeToSend > 0)
						&& ((sizeToSend + current->size) > maxSendSize)) {
					// We have a batch and the next will not fit in the buffer so send it
					IBMRAS_DEBUG_2(fine, "publishing batched message to %s of %d bytes",
							messageTopic.c_str(), sizeToSend);
					con.sendMessage(messageTopic, sizeToSend, dataToSend);
					sizeToSend = 0;
				}

				if (dataToSend
						&& ((sizeToSend + current->size) <= maxSendSize)) {
					// We are batching the messages and this will fit in the buffer
					// Batch the message in the buffer
					memcpy(dataToSend + sizeToSend, current->data,
							current->size);
					sizeToSend += current->size;

				} else {
					// Publish from bucket
					IBMRAS_DEBUG_2(fine, "publishing message to %s of %d bytes",
							messageTopic.c_str(), current->size);
					con.sendMessage(messageTopic, current->size, current->data);
				}
				current = current->next;
			}

			// Publish any remaining batched data
			if (dataToSend && (sizeToSend > 0)) {
				IBMRAS_DEBUG_2(fine, "publishing batched message to %s of %d bytes",
						messageTopic.c_str(), sizeToSend);
				con.sendMessage(messageTopic, sizeToSend, dataToSend);
			}
			ibmras::common::memory::deallocate(&dataToSend);

			con.sendMessage(messageTopic, 0, NULL);
			lock->release();
		}
	}
}

std::string Bucket::toString() {
	std::stringstream str;
	str << "Bucket [" << common::itoa(provID) << ":" << common::itoa(sourceID)
			<< "], capacity = " << common::itoa(capacity) << ", count = "
			<< common::itoa(count) << ", used = " << common::itoa(size)
			<< '\n';
	return str.str();
}

uint32 Bucket::getProvID() {
	return provID;
}

uint32 Bucket::getSourceID() {
	return sourceID;
}

std::string Bucket::getUniqueID() {
	return uniqueID;
}

}
}
} /* end namespace agent */
