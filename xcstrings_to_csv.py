#!/usr/bin/env python3

from pathlib import Path
import json
import sys
import csv

files = sys.argv[1:]


with open('output.csv', 'w') as csvfile:
    writer = csv.writer(csvfile, delimiter=',')
    writer.writerow(['key', 'en', 'pl'])
    for file in files:
        with open(file, 'r') as f:
            data = json.load(f)["strings"]
            for key, translations in data.items():
                if "pl" not in translations["localizations"]:
                    continue
                if "stringUnit" not in translations["localizations"]["en"]:
                    continue
                en, pl = [translations["localizations"][lang]["stringUnit"]["value"] for lang in ("en", "pl")]
                writer.writerow((key, en, pl))
                #  for lang, translation in translations["localizations"].items():
                    #  if "stringUnit" not in translation or lang not in ("en", "pl"):
                        #  continue
                    #  print(lang, translation["stringUnit"]["value"])
