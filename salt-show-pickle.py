#!/opt/saltstack/salt/bin/python3
import sys
import salt.payload
from pprint import pprint

if len(sys.argv) < 2:
    print("Usage: {} <path-to-data.p>".format(sys.argv[0]))
    sys.exit(1)

file_path = sys.argv[1]

try:
    with open(file_path, 'rb') as f:
        data = salt.payload.load(f)
    pprint(data)
except Exception as e:
    print("Error:", e)
# usage: python3 show_pickle.py /var/cache/salt/master/minions/<minionid>/data.p
