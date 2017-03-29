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


#ifndef ibmras_monitoring_monitoring_h
#define ibmras_monitoring_monitoring_h

#ifdef __cplusplus
extern "C"{
#endif

#ifndef PLUGIN_API_VERSION
#define PLUGIN_API_VERSION "1.0"
#endif

/* provide a default definition of DECL of the platform does not define one */
#ifndef DECL
#define DECL
#endif

#if defined(_WINDOWS)
  #if defined(EXPORT)
    #define DECL __declspec(dllexport)	/* required for DLLs to export the plugin functions */
  #else
    #define DECL __declspec(dllimport)
  #endif
  #define PLUGIN_API_DECL __declspec(dllexport)	/* required for DLLs to export the plugin functions */
#else
  #define PLUGIN_API_DECL
#endif

/*
 * API definitions for data sources to connect to the monitoring
 * agent.
 */

/* data from a source */
typedef struct monitordata {
	unsigned int provID;				/* provider ID, previously allocated during the source registration */
	unsigned int sourceID;			/* source ID, previously supplied by the source during registration */
	unsigned int size;				/* amount of data being provided */
	const char *data;			/* char array of the data to store */
#ifdef __cplusplus
	bool persistent;            /* persistent data will not be removed from the bucket */
#else
	int persistent;            /* persistent data will not be removed from the bucket */
#endif
} monitordata;

typedef monitordata* (*PULL_CALLBACK)(void);			/* shortcut definition for the pull source callback */
typedef void (*PULL_CALLBACK_COMPLETE)(monitordata*);	/* callback to indicate when the data source can free / re-use the memory */
typedef char* (*GET_CONFIG)(void);

/* common header for data sources */
typedef struct srcheader {
	unsigned int sourceID;			/* ID assigned by the provider - unique by provider */
	unsigned int capacity;			/* the amount of space in bytes that should be allocated for this source */
	const char *name;			/* null terminated C string */
	const char *description;	/* null terminated C string */
} srcheader;

typedef struct pushsource {
	srcheader header;			/* common source header */
#ifdef __cplusplus
	pushsource *next;			/* next source or null if this is the last one in the list */
#else
	struct pushsource *next;		/* next source or null if this is the last one in the list */
#endif
} pushsource;

typedef struct pullsource{
	srcheader header;			/* common source header */
#ifdef __cplusplus
	pullsource *next;			/* the next source or null if this is the last one in the list */
#else
	struct pullsource *next;			/* the next source or null if this is the last one in the list */
#endif
	unsigned int pullInterval;		/* time in seconds at which data should be pulled from this source */
	PULL_CALLBACK callback;
	PULL_CALLBACK_COMPLETE complete;
} pullsource;

/* definition for connectors */
typedef void* (*CONNECTOR_FACTORY)(const char* properties);	/* short cut for the function pointer to invoke in the connector library */

/* definition for receivers */
typedef void (*RECEIVE_MESSAGE)(const char* id, unsigned int size, void *data);	/* short cut for the function pointer to invoke in the receiver library */

/*
 * Enumeration levels to set for the logger
 */
enum loggingLevel {
	/* log levels are ranked with debug being the most verbose */
	none=0, warning, info, fine, finest, debug
};

typedef void (*pushData)(monitordata *data);
typedef int (*sendMessage)(const char * sourceId, unsigned int size,void *data);
#ifdef __cplusplus
typedef void (*exposedLogger)(loggingLevel lev, const char * message);
#else
typedef void (*exposedLogger)(enum loggingLevel lev, const char * message);
#endif
typedef const char * (*agentProperty)(const char * key);
typedef void (*setAgentProp)(const char* key, const char* value);
typedef void (*lifeCycle)();
#ifdef __cplusplus
typedef bool (*loadPropFunc)(const char* filename);
#else
typedef int (*loadPropFunc)(const char* filename);
#endif
typedef const char* (*getVer)();
typedef void (*setLogLvls)();
typedef void (*registerZipFn)(void(*)(const char*));
typedef void (*addPlgn)(const char*);

typedef struct agentCoreFunctions {
	pushData agentPushData;
	sendMessage agentSendMessage;
	exposedLogger logMessage;
	agentProperty getProperty;
} agentCoreFunctions;

typedef struct loaderCoreFunctions {
	lifeCycle init;
	lifeCycle initialize;
	lifeCycle start;
	lifeCycle stop;
	lifeCycle shutdown;
	exposedLogger logMessage;
	agentProperty getProperty;
	setAgentProp setProperty;
	loadPropFunc loadPropertiesFile;
	getVer getAgentVersion;
	setLogLvls setLogLevels;
	registerZipFn registerZipFunction;
    addPlgn addPlugin;

} loaderCoreFunctions;

DECL loaderCoreFunctions* loader_entrypoint();

typedef int (*PLUGIN_INITIALIZE)(const char* properties);
typedef pushsource* (*PUSH_SOURCE_REGISTER)(agentCoreFunctions aCF, unsigned int provID);
typedef void (*PUSH_CALLBACK)(monitordata* data);

#ifdef __cplusplus
}
#endif

#endif /* ibmras_monitoring_monitoring_h */



