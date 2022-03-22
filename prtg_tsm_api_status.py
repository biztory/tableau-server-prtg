import requests, json, sys, urllib3

# We'll disable warnings as we know TSM is insecure, but PRTG takes any printed content as response and thus we must... suppress these.
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# The PRTG Sensor passes the credentials we'll need as a command line argument, in the format of a JSON object. We'll take that and parse that.
data = json.loads(sys.argv[1])
params = dict(x.split('=') for x in data["params"].split(','))
tsm_username = data["linuxloginusername"]
tsm_password = data["linuxloginpassword"]
tableau_server_url = params["tableau_server_url"]

session = requests.Session()
server_tsm_api_url = "https://" + tableau_server_url + ":8850/api/0.5/"
login_url = server_tsm_api_url + "login"
logout_url = server_tsm_api_url + "logout"

headers = {
    "Content-Type": "application/json"
}

body = {
    "authentication": {
        "name": tsm_username,
        "password": tsm_password
    }
}

# Configure the session to authenticate with the provided credentials.
# Do not verify the SSL certificate because this is a self-signed certificate.
session = requests.Session()

# Sign in
login_resp = session.post(login_url, data=json.dumps(body), headers=headers, verify=False)

# Get status
status_response_body = session.get(server_tsm_api_url + "status", headers=headers, verify=False)
status_response_body_json = status_response_body.json()
# print(status_response_body_json)

# Flatten per service
status_services = []
for node in status_response_body_json["clusterStatus"]["nodes"]:
    for service in node["services"]:
        for instance in service["instances"]:
            status_services.append({
                "channel": node["nodeId"] + " - " + service["serviceName"] + "_" + instance["instanceId"],
                "value": 0 if instance["processStatus"].lower() in ["down", "error", "unlicensed", "warning"] else 1,
                "warning": 1 if instance["processStatus"].lower() in ["down", "error", "unlicensed", "warning"] else 0
            })

return_json = {
    "prtg": {
        "result": status_services
    }
}

# Some manipulations (end, strip) to ensure there are no newlines
print(json.dumps(return_json).strip(), end="")
