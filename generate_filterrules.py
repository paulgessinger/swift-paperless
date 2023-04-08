#!/usr/bin/env python3

import sys
import urllib.request
import re
import dirtyjson
import yaml
from pathlib import Path
from dataclasses import dataclass
from datetime import datetime
from jinja2 import Environment, FileSystemLoader

# url = sys.argv[1]
url = "https://raw.githubusercontent.com/paperless-ngx/paperless-ngx/b948750d558b58018d1d3393db145d162d44fceb/src-ui/src/app/data/filter-rule-type.ts"

response = urllib.request.urlopen(url)

code = response.read().decode("utf-8")

name_by_id = {}
id_by_name = {}
for name, id in re.findall(r"export const (FILTER_[A-Z_]+) = (\d+)", code):
    name_by_id[id] = name
    id_by_name[name] = id


groups = re.findall(r"{.*?}", code, re.MULTILINE | re.DOTALL)


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
    #  print(group)

    prepped = re.sub(r"(FILTER_[A-Z_]+)", r'"\1"', group)
    prepped = re.sub(r"(\w+):", r'"\1":', prepped)
    prepped = prepped.replace("'", '"')
    obj = dirtyjson.loads(prepped)
    #  print(obj)

    rule_types.append(
        FilterRuleType(
            id=int(id_by_name[obj["id"]]),
            name=obj["id"],
            filtervar=obj["filtervar"],
            isnull_filtervar=obj.get("isnull_filtervar"),
            datatype=obj["datatype"],
            multi=obj["multi"],
            default=obj.get("default", False),
        )
    )

    #  print(rule_types[-1])
    #  print(rule_types[-1].swift_name)
    #  print("")

env = Environment(loader=FileSystemLoader(Path(__file__).parent))
env.filters["to_camel"] = to_camel

template = env.get_template("filter_rules.swift.jinja2")

print(template.render(rule_types=rule_types, url=url, date=datetime.now()))

#  print(ids)
