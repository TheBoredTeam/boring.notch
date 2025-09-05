import sys
import re

version = sys.argv[1] if len(sys.argv) > 1 else ''
match = re.match(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-(alpha|beta|rc)\.(\d+))?', version)
if match is not None:
    major = int(match.group(1) or 0)
    minor = int(match.group(2) or 0)
    patch = int(match.group(3) or 0)
    if match.group(4):
        type_str = match.group(4)
        type_num = {'alpha': 1, 'beta': 2, 'rc': 3}[type_str]
        number = int(match.group(5))
    else:
        type_num = 9
        number = 0
    build_num = major * 10000000 + minor * 100000 + patch * 1000 + type_num * 100 + number
    print('%09d' % build_num)
else:
    import sys
    sys.stderr.write(f"Invalid version format: {version}\n")
    sys.exit(1)
