# SwiftMetrics REST API


The REST API enables the collection of metrics from the running Swift application. The API context root will be the server's default endpoint plus /swiftmetrics eg.
`http://localhost:9080/swiftmetrics/`


## Enabling the REST API


To enable the REST API in your program, you must include the **SwiftMetricsREST** module in your program

```swift
import SwiftMetrics
import SwiftMetricsREST

// Enable SwiftMetrics Monitoring
let sm = try SwiftMetrics()

// Pass SwiftMetrics to SwiftMetricsREST
let smr = try SwiftMetricsREST(swiftMetricsInstance : sm)
```

If you have multiple modules that define a Kitura Router, such as **SwiftMetricsDash** or **SwiftMetricsPrometheus**, you should define a Router() object and pass that into the initialization functions of those modules

```swift
import KituraNet
import SwiftMetrics
import SwiftMetricsDash
import SwiftMetricsPrometheus
import SwiftMetricsREST

// Initialise router object
var router = Router()

// Enable SwiftMetrics Monitoring
let sm = try SwiftMetrics()

// Pass SwiftMetrics to SwiftMetricsREST
let smd = try SwiftMetricsDash(swiftMetricsInstance : sm, endpoint: router)
let smp = try SwiftMetricsPrometheus(swiftMetricsInstance : sm, endpoint: router)
let smr = try SwiftMetricsREST(swiftMetricsInstance : sm, endpoint: router)
```


## Usage
Metrics are accumulated in a **collection**.
The start time of the metrics accumulation is from either creation of the collection
`POST <context_root>/api/v1/collections`
or from the time of a clear request
`PUT <context_root>/api/v1/collection/{id}`.


1. Create a new metrics collections. Metrics are recorded from collection creation time.
  - `POST <context_root>/api/v1/collections`
  - returned URI `collections/3`
2. Retrieve the metrics from the collection at required interval.
  - `GET <context_root>/api/v1/collections/3`
  - Process the returned JSON format metrics.
  - Optionally clear the metrics from the collection.<br>
  `PUT <context_root>/api/v1/collections/3`
3. Delete the collection.
  - `DELETE <context_root>/api/v1/collections/3`



## API reference

* [List current metrics collections](#list_collections)
* [Create a new metrics collection](#create_collection)
* [Retrieve metrics from a collection](#retrieve_collection)
* [Clear metrics from collection](#clear_collection)
* [Delete a metrics collection](#delete_collection)


### <a name="list_collections"></a>List metrics collections

Returns a list of the current metrics collections URIs.

* **URL**

  `/api/v1/collections`

* **Method**

  `GET`


* **URL Params**

  None

* **Data Params**

  None

* **Success Responses**

  * **Code:** `200 (OK)`
  * **Content:** The uris of existing **collections**.
  Example:
  ```JSON
  {
    "collectionUris": ["http://localhost:9080/javametrics/api/v1/collections/0",
    "http://localhost:9080/javametrics/api/v1/collections/1"]
  }
  ```

* **Error Responses**

  * na

### <a name="create_collection"></a>Create metrics collection


Creates a new metrics collection. The collection uri is returned in the Location header.

A maximum of 10 collections are allowed at any one time. Return code 400 indicates too many collections.


* **URL**

  `/api/v1/collections`

* **Method**

  `POST`

* **URL Params**

  None

* **Data Params**

  None

* **Success Responses**

  * **Code:** `201 (CREATED)`
  * **Content:** The uri of the created **collection**.
  Example:
  ```JSON
   {"uri":"collections/1"}
  ```

* **Error Responses**

  * **Code:** `400 (BAD REQUEST)`
  * **Content** none


### <a name="retrieve_collection"></a>Retrieve metrics collection

Returns the metrics from the specified collection.

* **URL**

  `/api/v1/collections/{id}`

* **Method**

  `GET`

* **URL Params**

  `Required: id=[integer]`

* **Data Params**

  None

* **Success Responses**

  * **Code:** `200 (OK)`
  * **Content:** JSON representation of the metrics in the **collection**.
  Example:
```JSON
{
  "id" : 0,
  "httpUrls" : {
    "units" : {
      "longestResponseTime" : "ms",
      "hits" : "count",
      "averageResponseTime" : "ms"
    },
    "data" : [
      {
        "averageResponseTime" : 0.78173828125,
        "longestResponseTime" : 3.496337890625,
        "url" : "http://localhost:8080/swiftmetrics/api/v1/collections",
        "hits" : 13
      }
    ]
  },
  "memory" : {
    "units" : {
      "systemPeak" : "bytes",
      "processMean" : "bytes",
      "systemMean" : "bytes",
      "processPeak" : "bytes"
    },
    "data" : {
      "systemPeak" : 17146236928,
      "processMean" : 39254697,
      "systemMean" : 17132246356,
      "processPeak" : 39403520
    }
  },
  "time" : {
    "units" : {
      "end" : "UNIX time (ms)",
      "start" : "UNIX time (ms)"
    },
    "data" : {
      "start" : 1532621816291,
      "end" : 1532621835099
    }
  },
  "cpu" : {
    "units" : {
      "systemPeak" : "decimal fraction",
      "processMean" : "decimal fraction",
      "systemMean" : "decimal fraction",
      "processPeak" : "decimal fraction"
    },
    "data" : {
      "systemPeak" : 0.099996000528335571,
      "processMean" : 0.00043332966985569027,
      "systemMean" : 0.060481000691652298,
      "processPeak" : 0.0008126390166580677
    }
  }
}
```

* **Error Responses**

  * **Code:** `404 (NOT_FOUND)`
  * **Content:** none


### <a name="clear_collection"></a>Clear metrics collection

Clear the metrics in a collection.

* **URL**

  `/api/v1/collections/{id}`

* **Method**

  `PUT`

* **URL Params**

  `Required: id=[integer]`

* **Data Params**

  None

* **Success Responses**

  * **Code:** `204 (NO_CONTENT)`
  * **Content:** none

* **Error Responses**
  * **Code:** `404 (NOT_FOUND)`
  * **Content:** none


### <a name="delete_collection"></a>Delete collection

Delete a collection.

* **URL**

  `/api/v1/collections/{id}`

* **Method**

  `DELETE`

* **URL Params**

  `Required: id=[integer]`

* **Data Params**

  None

* **Success Responses**

  * **Code:** `204 (NO_CONTENT)`
  * **Content:** none

* **Error Responses**
  * **Code:** `404 (NOT_FOUND)`
  * **Content:** none
