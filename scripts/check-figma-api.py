#!/usr/bin/env python3
"""Read-only Figma token probe. Invoke through bin/figma-env; never print auth/body."""

import json
import os
import sys
import urllib.error
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def main():
    token = os.environ.pop('FIGMA_TOKEN', '')
    if not token:
        print('Figma API: token missing; run make figma-api-check', file=sys.stderr)
        return 1
    request = urllib.request.Request('https://api.figma.com/v1/me',
                                     headers={'X-Figma-Token': token})
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=30) as response:
            data = json.load(response)
            if response.status != 200 or not isinstance(data, dict) or not data.get('id'):
                print('Figma API: unexpected response; contents hidden', file=sys.stderr)
                return 1
        print('Figma API: authenticated read succeeded (HTTP 200; identity and token hidden)')
        return 0
    except urllib.error.HTTPError as error:
        print(f'Figma API: HTTP {error.code}; response body and token hidden', file=sys.stderr)
        if error.code in (401, 403):
            print('Check token validity and current_user:read permission after renewal.', file=sys.stderr)
        return 1
    except (OSError, ValueError):
        print('Figma API: request failed; details hidden', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
