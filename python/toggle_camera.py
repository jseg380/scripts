#!/bin/python

# The config file is owned by root so sudo is necessary to edit this file
from os import geteuid
from sys import argv
from subprocess import call

with open('/etc/modprobe.d/nocamera.conf', 'r') as config_file:
    enabled = 'enabled' in config_file.readline().lower()

if geteuid() != 0:
    print(f'Camera is currently {"enabled" if enabled else "disabled"}')

    answer = input(f'Do you want to {"disable" if enabled else "enable"} it? [Y/n] ')
    if not 'y' in answer.lower():
        exit()

    # Run the script with sudo if it has not been ran with it already
    call(['sudo', 'python3', argv[0]])
    exit()
else:
    configs = {
        'enabled': "# Enabled\n# Do not block loading of 'uvcvideo' module (web camera)\n#blacklist uvcvideo",
        'disabled': "# Disabled\n# Do not load the 'uvcvideo' module (web camera)\nblacklist uvcvideo"
    }

    with open('/etc/modprobe.d/nocamera.conf', 'w') as config_file:
        if enabled:
            print('Turning camera off')
            config_file.write(configs['disabled'])
        else:
            print('Turning camera on')
            config_file.write(configs['enabled'])

        print('Restart for effects to take place')
