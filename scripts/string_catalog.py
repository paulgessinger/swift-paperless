from pathlib import Path
import pydantic
from typing import IO, cast
import io


class StringUnit(pydantic.BaseModel):
    state: str
    value: str


class LocalizationItem(pydantic.BaseModel):
    string_unit: StringUnit | None = pydantic.Field(alias="stringUnit")


class StringCatalogString(pydantic.BaseModel):
    extraction_state: str = pydantic.Field(alias="extractionState")
    localizations: dict[str, LocalizationItem]


class StringCatalog(pydantic.BaseModel):
    source_language: str = pydantic.Field(alias="sourceLanguage")
    strings: dict[str, StringCatalogString]

    def as_dict(self) -> dict[str, dict[str, str]]:
        return {
            key: {
                lang: item.string_unit.value
                for lang, item in value.localizations.items()
                if item.string_unit is not None
            }
            for key, value in self.strings.items()
        }


def load(data: str | bytes) -> StringCatalog:
    return StringCatalog.model_validate_json(data)
