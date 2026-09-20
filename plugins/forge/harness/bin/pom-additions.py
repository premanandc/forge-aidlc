#!/usr/bin/env python3
"""Print build inputs added to pom.xml between HEAD and the staged index.

Used by bin/guard.sh. Compares two things that let new code into the build:
  - direct dependencies: /project/dependencies/dependency
  - plugins, in the main build and in every profile: //build/plugins/plugin

Version pins and exclusions under dependencyManagement change versions of code that is already
present and are not reported. Output is one line of space-separated groupId:artifactId pairs
(empty when nothing was added). Exits non-zero if either pom cannot be parsed, so the caller can
fail closed. Uses xml.etree, the same document model Maven sees; no regex over XML.
"""

import subprocess
import sys
import xml.etree.ElementTree as ET

NS = "{http://maven.apache.org/POM/4.0.0}"


def show(ref):
    r = subprocess.run(["git", "show", ref], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def ga(element):
    g = element.findtext(f"{NS}groupId") or element.findtext("groupId") or "org.apache.maven.plugins"
    a = element.findtext(f"{NS}artifactId") or element.findtext("artifactId") or "?"
    return f"{g.strip()}:{a.strip()}"


def inputs(xml):
    if not xml.strip():
        return set()
    # A pom has no business declaring a DTD or entities; refuse rather than risk XXE or
    # entity-expansion tricks against the parser (defusedxml is not a given on every machine).
    if "<!DOCTYPE" in xml or "<!ENTITY" in xml:
        raise ET.ParseError("pom.xml declares a DOCTYPE or ENTITY; refusing to parse")
    root = ET.fromstring(xml)
    found = set()
    for dep in root.findall(f"./{NS}dependencies/{NS}dependency") + root.findall("./dependencies/dependency"):
        found.add("dependency " + ga(dep))
    for plugin in root.iter(f"{NS}plugin"):
        if plugin.find(f"{NS}artifactId") is not None:
            found.add("plugin " + ga(plugin))
    for plugin in root.iter("plugin"):
        if plugin.find("artifactId") is not None:
            found.add("plugin " + ga(plugin))
    return found


try:
    added = inputs(show(":pom.xml")) - inputs(show("HEAD:pom.xml"))
except ET.ParseError as e:
    print(f"PARSE_ERROR {e}", file=sys.stderr)
    sys.exit(1)
print(" ".join(sorted(added)))
