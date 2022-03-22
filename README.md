# tableau-server-prtg

This is an example of some resources used to monitor a Tableau Server with PRTG. A "generic" implementation with an external Tableau Server (penguin.biztory.com) has been performed. It is documented here, with the intention of enabling you to apply the same elsewhere.

The following requirements for tracking come to mind:

* Overall **application availability**: is the application reachable/up?
* Specific **application service status**: are all components of Tableau (VizQL, Backgrounders, ...) healthy?
* Monitoring of important **events in the application**:
  * Did an extract refresh fail?
  * Is performance of reports degraded?
  * ...
* **Licence expiry status** (not yet added): are our licences still valid for long enough, or do we have to start looking into renewal?

We are assuming that "generic" OS and system-level resources are already being monitored, including CPU, Memory, Disk, etc.

## Prerequisites

As we will be approaching some specific components of Tableau Server, the following needs to be accessible:

* **TSM API**: web service (API) on **port 8850**. [Documented here](https://help.tableau.com/v0.0/api/tsm_api/en-us/docs/authentication.htm).
  * Port must be opened in firewall (the server's and on the network).
  * The user for authenticating to the API is a user on the server part of the tsmadmin  group.
* **Workgroup database** (Tableau Server's internal database, or "repository"): Postgres database on **port 8060**.
  * Port must be opened in firewall (the server's and on the network).
  * [Access must have been enabled](https://help.tableau.com/current/server/en-us/perf_collect_server_repo.htm#enable-access-to-the-tableau-server-repository) in the configuration.

## Setup

### Device

One device can be set up for each server/virtual machine that is part of Tableau Server. Currently we are only working with single-node environments, i.e. the TEST environment is a single server, in which case all sensors apply to that one node. In a multi-node environment, which may potentially be relevant in the future, not all sensors might be relevant to all nodes; this will be specified for the sensors below.

We will specify the device's **Linux Credentials** (username/password) as these will be used for the Application Services Status Sensor. We'll also specify Database Credentials for the repository, more details on that below.

### Sensor: Overall Availability

Used to check if the application as a whole is reachable.

* Sensor Name (suggested): Overall Availability (HTTP)
* Type: [HTTP Sensor](https://www.paessler.com/manuals/prtg/http_sensor)
* Nodes/devices: applies to each node with a Tableau Gateway process, or the load balancer.
* Configuration:
  * Timeout: 30s
  * URL: https://penguin.biztory.com/favicon.ico
  * Request Method: HEAD
  * Scanning Interval: 60s

### Sensor: Application Services Status

Uses the [TSM API](https://help.tableau.com/v0.0/api/tsm_api/en-us/docs/tsm-reference.htm#get-server-status) to get the status of Tableau Server's component services, verifying whether these are are in the right state. [Authentication](https://help.tableau.com/v0.0/api/tsm_api/en-us/docs/authentication.htm) for this API uses an initial POST request with a body containing username and password; subsequent calls use a cookie set by the initial authentication call. Because of this complexity, we'll use a custom Python Advanced Script Sensor.

The script will take care of authentication, as well as getting and returning the results on the actual status REST API call in a JSON format. We will transmit the device's Linux credentials to the script, as these are the ones used for authentication to the API. Note that we are also using the Python requests module, which we need to [install for PRTG's Python runtime](https://kb.paessler.com/en/topic/84447-add-python-modules). Make sure you install these as an Administrator, otherwise they will end up in the user's site directory and not be available for PRTG's Python. Finally an "Additional Parameter" is also used to specify the Tableau Server URL (without port, without HTTPS, e.g. `penguin.biztory.com` or). The documentation for this Sensor is particularly useful as a reference ([Python Sensor](https://www.paessler.com/manuals/prtg/python_script_advanced_sensor), [Custom Sensor return format](https://www.paessler.com/manuals/prtg/custom_sensors#advanced_sensors)).

* Sensor Name (suggested): Application Services Status (Python)
* Type: [Python Script Advanced Sensor](https://www.paessler.com/manuals/prtg/python_script_advanced_sensor).
* Nodes/devices: applies to the primary/first node only.
* Configuration:
  * Python Script: [prtg_tsm_api_status.py](./prtg_tsm_api_status.py), on the PRTG server as documented.
  * Device credentials: Transmit Linux credentials
  * Additional parameters: `tableau_server_url=penguin.biztory.com`

### Sensor: Tableau Application Data (PostgreSQL)
This sensor queries Tableau Server's own internal database (sometimes referred to as the "workgroup" or "repository") to surface information about the application's tasks and properties. For example, Tableau Server periodically performs a task that consists of connecting to a database to refresh a report's data; if this task is unsuccessful, we can determine that by querying the database.

Similarly to the Custom Python Script Sensor above, we will:

* Save the credentials at the level of the device ([Credentials for Database Management Systems](https://www.paessler.com/manuals/prtg/device_settings#dbcredentials)), which apply to Postgres as well. We also set the DBMS port to 8060 here, which is the custom port used by Tableau's Postgres instance.
* Save the queries/query we'll use in a file, to be saved on the PRTG server as documented.

The steps for setup are to first ensure the file with the query is in place, after which we can add the Sensor and configure all its Channels, i.e. each of the results it'll return = each metric we want to check. It is not possible to configure additional Channels after the Sensor has already been created. Once the Sensor is set up, limits can be defined for each Channel, e.g. Max 1 Failed Extract in the Last 60 Minutes, etc.

* Sensor Name (suggested): Tableau Application Data (PostgreSQL)
* Type: [PostgreSQL Sensor](https://www.paessler.com/manuals/prtg/postgresql_sensor).
* Nodes/devices: applies to the node hosting the repository only.
* Configuration:
  * Database: workgroup
  * SSL Mode: Allow
  * SQL Query File: [prtg_workgroup_application_stats.sql](./prtg_workgroup_application_stats.sql), on the PRTG server as documented.
  * Data Processing: Process data table
  * Handle DBNull in Channel Values as: Number 0
  * Select Channel Value by: Key value pair
  * Channel 1 (as example, the rest is analogous referring to the "name" column keys of the query):
    * Name: Number of Failed Extracts, Last 60 min
    * Channel Key: number_of_failed_extracts_last_60min
    * Scanning interval: 10 minutes
  * Limits for each Channel TBD based on preference, e.g.:
    * Extracts: Avg Delay (s) in the Last 4 Hours:
      * Upper Error: 600s
      * Upper Warning: 300s
    * Extracts: Number of Failed in the Last 60 Minutes
      * Upper Error: 1
    * Extracts: Relative Avg Duration (%), Last 8 Hours vs Last 3 Weeks
      * Upper Error: 5
      * Upper Warning: 2
    * Performance: Avg Load Time (s) for Top 10 Views
      * Upper Error: 30
      * Upper Warning: 12
