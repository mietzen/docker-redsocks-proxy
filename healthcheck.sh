#!/bin/bash

set -eo pipefail

pgrep redsocks
if [[ "${DNSCrypt_Active}" == 'true' ]]; then
    pgrep dnscrypt-proxy
fi
