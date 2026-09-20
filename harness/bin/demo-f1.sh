#!/usr/bin/env bash
# Flow F1 through the running application with curl (Checkpoint 3).
#   bin/demo-f1.sh [base-url] [npi]
# Default NPI 1234567893 is ten digits and screens GREEN; pass 12345 to see the
# analyst path and the advisor's draft.
set -euo pipefail
BASE=${1:-http://localhost:8080}
NPI=${2:-1234567893}

say() { printf '\n### %s\n' "$*"; }
json() { python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), indent=2))'; }

say "1. Create a DRAFT application (POST /applications)"
CREATED=$(curl -sS -X POST "$BASE/applications" -H 'Content-Type: application/json' -d "{
  \"npi\": \"$NPI\", \"providerType\": \"PHYSICIAN\",
  \"licenseNumber\": \"IL-4471\", \"licenseState\": \"IL\",
  \"serviceAddress\": {\"line1\": \"100 Main St\", \"city\": \"Springfield\", \"state\": \"IL\", \"postalCode\": \"62701\"}
}")
echo "$CREATED" | json
ID=$(echo "$CREATED" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')

say "2. Submit it (POST /applications/$ID/submit) -> publishes ApplicationSubmitted"
curl -sS -X POST "$BASE/applications/$ID/submit" | json

say "3. Poll until determined (GET /applications/$ID); screening and decision run asynchronously"
for i in $(seq 1 20); do
  VIEW=$(curl -sS "$BASE/applications/$ID")
  STATUS=$(echo "$VIEW" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')
  [ "$STATUS" = "DETERMINED" ] && break
  sleep 0.5
done
echo "$VIEW" | json

say "4. The advisor's draft, if a case awaits an analyst (GET /applications/$ID/determination/draft)"
curl -sS -w '\nHTTP %{http_code}\n' "$BASE/applications/$ID/determination/draft"

say "5. Module structure and events as the running app sees them (GET /actuator/modulith)"
curl -sS "$BASE/actuator/modulith" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps({k: {"dependencies": [x.get("target") for x in v.get("dependencies", [])]} for k, v in d.items()}, indent=2))'

say "6. The generated contract is served by the app itself"
curl -sS -o /dev/null -w 'GET /api-docs/index.html -> HTTP %{http_code}, %{size_download} bytes\n' "$BASE/api-docs/index.html"
