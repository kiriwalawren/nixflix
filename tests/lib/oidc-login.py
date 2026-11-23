"""Exercise a test-only Dex -> Arr authorization-code login in the VM."""

import sys
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup

name = sys.argv[1]
assert name in {"radarr", "sonarr", "sonarr-anime"}, name
BASE = f"https://{name}.test"
session = requests.Session()
session.trust_env = False
session.verify = "/etc/ssl/certs/ca-certificates.crt"

response = session.get(BASE + "/", timeout=30)
for _ in range(10):
    if "dex.test" in response.url and response.status_code == 200:
        break
    page = BeautifulSoup(response.text, "html.parser")
    link = page.find(
        "a",
        href=lambda href: href and ("/login" in href.lower() or "oidc" in href.lower()),
    )
    assert link, f"No OIDC sign-in link found at {response.url}: {response.text[:500]}"
    response = session.get(urljoin(response.url, link["href"]), timeout=30)
else:
    raise AssertionError(f"Never reached Dex login: {response.url}")

# Dex's connector selection screen links to the mockPassword connector.
page = BeautifulSoup(response.text, "html.parser")
link = page.find("a", href=lambda href: href and "/auth/mock" in href)
if link:
    response = session.get(urljoin(response.url, link["href"]), timeout=30)
    page = BeautifulSoup(response.text, "html.parser")

form = page.find("form")
assert form, f"Dex login form not found at {response.url}: {response.text[:500]}"
fields = {
    field["name"]: field.get("value", "")
    for field in form.find_all("input")
    if field.get("name")
}
fields.update(login="testuser", password="testpassword")
response = session.post(
    urljoin(response.url, form.get("action", "")), data=fields, timeout=30
)
assert response.status_code == 200, (
    response.url,
    response.status_code,
    response.text[:500],
)
assert urlparse(response.url).hostname == f"{name}.test", response.url
assert any("/signin-oidc" in step.url for step in response.history), [
    step.url for step in response.history
]

# An authenticated UI request must not start another OIDC challenge.
response = session.get(BASE + "/", timeout=30)
assert (
    response.status_code == 200 and urlparse(response.url).hostname == f"{name}.test"
), response.url
print(f"PASS: {name} OIDC login completed through Dex")
