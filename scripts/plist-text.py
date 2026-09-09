"""Read-only Git textconv for XML/binary plists on either OS."""
import json
import plistlib
import sys

with open(sys.argv[1], 'rb') as stream:
    value = plistlib.load(stream)
print(json.dumps(value, indent=2, ensure_ascii=True, sort_keys=True, default=str))
