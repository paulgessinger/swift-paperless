#!/usr/bin/env python3

import sys
import urllib.request
import re
import dirtyjson
import json
from pathlib import Path
import tempfile
from dataclasses import dataclass
from jinja2 import Environment, FileSystemLoader
from subprocess import check_call, check_output, CalledProcessError
import argparse

input_file = "src-ui/src/app/data/filter-rule-type.ts"

parser = argparse.ArgumentParser()
parser.add_argument("--url", type=str, default=f"https://raw.githubusercontent.com/paperless-ngx/paperless-ngx/dev/{input_file}")
parser.add_argument("--output", type=argparse.FileType("w"), default=sys.stdout)

args = parser.parse_args()

def swiftformat(file: Path) -> None: pass
try:
    exe = check_output(["which", "swiftformat"]).decode("utf-8").strip()
    def swiftformat(file: Path) -> None:
        check_call([exe, "--swiftversion", "5", str(file)])
except CalledProcessError:
    pass

try:
    gh = check_output(["which", "gh"]).decode("utf-8").strip()
    raw = check_output([gh, "api",
                        f"repos/paperless-ngx/paperless-ngx/commits?path={input_file}"]).decode("utf-8")
    commit_info = json.loads(raw)
    commit_sha = commit_info[0]["sha"]
    commit_url = commit_info[0]["html_url"]
    commit_date = commit_info[0]["commit"]["committer"]["date"]
except CalledProcessError:
    commit_sha = "0"
    commit_url = "Unknown"
    commit_date = "Unknown"
    pass

response = urllib.request.urlopen(args.url)

code = response.read().decode("utf-8")

name_by_id = {}
id_by_name = {}
for name, id in re.findall(r"export const (FILTER_[A-Z_]+) = (\d+)", code):
    name_by_id[id] = name
    id_by_name[name] = id


start_type_info = code.index("export const FILTER_RULE_TYPES: FilterRuleType[] = [")
groups = re.findall(r"{.*?}", code[start_type_info:], re.MULTILINE | re.DOTALL)

def to_camel(v: str) -> str:
    parts = v.split("_")
    parts = [p.lower().capitalize() for p in parts]
    parts[0] = parts[0].lower()
    return "".join(parts)


@dataclass
class FilterRuleType:
    id: int
    name: str
    filtervar: str
    isnull_filtervar: str
    datatype: str
    multi: bool
    default: bool

    @property
    def swift_name(self) -> str:
        parts = self.name.split("_")[1:]
        parts[0] = parts[0].lower()
        for i, part in enumerate(parts[1:], 1):
            parts[i] = part.lower().capitalize()
        return "".join(parts)


rule_types = []

for group in groups[:-1]:

    prepped = re.sub(r"(FILTER_[A-Z_]+)", r'"\1"', group)
    prepped = re.sub(r"DataType\.(\w+)", r'"\1"', prepped)
    prepped = re.sub(r"(\w+):", r'"\1":', prepped)
    prepped = prepped.replace("'", '"')
    try:
        obj = dirtyjson.loads(prepped)
    except:
        print(prepped)
        raise

    try:
        rule_types.append(
            FilterRuleType(
                id=int(id_by_name[obj["id"]]),
                name=obj["id"],
                filtervar=obj["filtervar"],
                isnull_filtervar=obj.get("isnull_filtervar"),
                datatype=obj["datatype"].lower()[0]+obj["datatype"][1:],
                multi=obj["multi"],
                default=obj.get("default", False),
            )
        )
    except:
        print(obj)
        raise

env = Environment(loader=FileSystemLoader(Path(__file__).parent))
env.filters["to_camel"] = to_camel

template = env.get_template("filter_rules.swift.jinja2")

with tempfile.TemporaryDirectory() as tmpdir:

    file = Path(tmpdir) / "filter_rules.swift"
    with file.open("w") as f:
        f.write(template.render(rule_types=rule_types, url=args.url, commit_sha=commit_sha, commit_date=commit_date, commit_url=commit_url))

    swiftformat(file)

    args.output.write(file.read_text().strip()+"\n")
