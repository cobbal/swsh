#!/bin/zsh

set -euo pipefail

GITHUB_TOKEN=${GITHUB_TOKEN:-$(cat ~/.config/secrets/semantic-release-github-token)}

curl -v \
     -H "Accept: application/vnd.github.everest-preview+json" \
     -H "Authorization: token ${GITHUB_TOKEN}" \
     https://api.github.com/repos/cobbal/swsh/dispatches \
     -d '{ "event_type": "semantic-release" }'
