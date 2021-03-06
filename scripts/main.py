#!/usr/bin/env python

# imports
import subprocess
import yaml

# defs
service_file = "../services/services.yaml"

def do_work():
    # load
    with open(service_file, 'r') as stream:
        data = yaml.safe_load(stream)
    
    # run script
    for service in data["service"]:
        services = "\"" + ' '.join(service["domains"]) + "\""
        stg = "--staging" if service["production"] == False else ""
        
        # deploy service
        p = subprocess.Popen([
            './deploy.sh', 
            '-h', service["host"], 
            '-p', str(service["port"]), 
            '-s', service["name"], 
            '-e', service["email"], 
            '--path', service["path"],
            stg, 
            '-d', services
        ])
        ex = p.wait()

# just work
if __name__ == "__main__":
    do_work()