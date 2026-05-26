"""Pixel-based text wrapping with hyphenation support."""

import re
from dataclasses import dataclass
from typing import Optional

from PIL import ImageFont

try:
    from pyphen import Pyphen

    PYPHEN_AVAILABLE = True
except ImportError:
    PYPHEN_AVAILABLE = False
    Pyphen = None


# Map app locales to pyphen language codes
LOCALE_TO_PYPHEN = {
    # English variants
    "en": "en_US",
    "en-US": "en_US",
    "en-GB": "en_GB",
    "en-AU": "en_GB",
    "en-CA": "en_US",
    # German
    "de": "de_DE",
    "de-DE": "de_DE",
    # French
    "fr": "fr_FR",
    "fr-FR": "fr_FR",
    "fr-CA": "fr_FR",
    # Spanish
    "es": "es_ES",
    "es-ES": "es_ES",
    "es-MX": "es_ES",
    # Italian
    "it": "it_IT",
    # Dutch
    "nl": "nl_NL",
    "nl-NL": "nl_NL",
    # Polish
    "pl": "pl_PL",
    "pl-PL": "pl_PL",
    # Danish
    "da": "da_DK",
    "da-DK": "da_DK",
    # Turkish
    "tr": "tr_TR",
    # Portuguese
    "pt": "pt_PT",
    "pt-PT": "pt_PT",
    "pt-BR": "pt_BR",
    # Russian
    "ru": "ru_RU",
    # Swedish
    "sv": "sv_SE",
    # Norwegian
    "no": "nb_NO",
    "nb": "nb_NO",
    "nb-NO": "nb_NO",
    # Finnish
    "fi": "fi_FI",
    # Czech
    "cs": "cs_CZ",
    # Slovak
    "sk": "sk_SK",
    # Hungarian
    "hu": "hu_HU",
    # Romanian
    "ro": "ro_RO",
    # Croatian
    "hr": "hr_HR",
    # Ukrainian
    "uk": "uk_UA",
    # Greek
    "el": "el_GR",
    # Catalan
    "ca": "ca_ES",
}

# Languages where hyphenation is not supported or inappropriate
HYPHENATION_UNSUPPORTED = {
    "zh-Hans",
    "zh-Hant",
    "zh",
    "ja",
    "ko",
    "ar-SA",
    "ar",
    "he",
    "th",
    "hi",
    "vi",
}


@dataclass
class TextWrapConfig:
    """Configuration for text wrapping."""

    max_width: int
    hyphenate: bool = True
    hyphen_char: str = "-"
    min_chars_before_hyphen: int = 2
    min_chars_after_hyphen: int = 2


@dataclass
class WrappedLine:
    """A single wrapped line of text."""

    text: str
    width: float
    ends_with_hyphen: bool = False


def measure_text(font: ImageFont.FreeTypeFont, text: str) -> float:
    """Measure the width of text in pixels."""
    if not text:
        return 0.0
    return font.getlength(text)


def get_pyphen_dict(locale: str) -> Optional["Pyphen"]:
    """Get pyphen dictionary for locale, or None if unavailable."""
    if not PYPHEN_AVAILABLE:
        return None

    normalized = locale.replace("_", "-")

    # Check if hyphenation is unsupported for this locale
    if normalized in HYPHENATION_UNSUPPORTED:
        return None
    base = normalized.split("-")[0]
    if base in HYPHENATION_UNSUPPORTED:
        return None

    # Find pyphen code
    pyphen_code = LOCALE_TO_PYPHEN.get(normalized)
    if pyphen_code is None:
        pyphen_code = LOCALE_TO_PYPHEN.get(base)

    if pyphen_code is None:
        # Try to use the locale directly
        pyphen_code = normalized.replace("-", "_")

    try:
        return Pyphen(lang=pyphen_code)
    except Exception:
        # Fallback to English if locale not available
        try:
            return Pyphen(lang="en_US")
        except Exception:
            return None


def find_hyphenation_point(
    word: str,
    font: ImageFont.FreeTypeFont,
    available_width: float,
    current_line_width: float,
    pyphen_dict: Optional["Pyphen"],
    config: TextWrapConfig,
) -> tuple[str, str] | None:
    """
    Find best hyphenation point for a word to fit in available width.

    Returns (first_part_with_hyphen, remaining) or None if no valid split.
    """
    if pyphen_dict is None:
        return None

    # Calculate how much space we have for the first part + hyphen
    space_for_word = available_width - current_line_width
    if current_line_width > 0:
        # Account for space before word
        space_for_word -= measure_text(font, " ")

    # pyphen.iterate() yields pairs from longest first part to shortest
    for first, second in pyphen_dict.iterate(word):
        # Ensure minimum characters on each side
        if len(first) < config.min_chars_before_hyphen:
            continue
        if len(second) < config.min_chars_after_hyphen:
            continue

        first_with_hyphen = first + config.hyphen_char
        width = measure_text(font, first_with_hyphen)

        if width <= space_for_word:
            return (first_with_hyphen, second)

    return None


def normalize_whitespace(text: str) -> str:
    """Normalize whitespace: replace newlines with spaces, collapse multiple spaces."""
    # Replace all whitespace (including newlines) with single spaces
    return re.sub(r"\s+", " ", text).strip()


def wrap_text_pixel(
    text: str,
    font: ImageFont.FreeTypeFont,
    config: TextWrapConfig,
    locale: str = "en",
) -> list[WrappedLine]:
    """
    Wrap text to fit within max_width pixels, using hyphenation when needed.

    Args:
        text: The text to wrap
        font: PIL ImageFont to use for measurement
        config: Wrapping configuration
        locale: Locale code for hyphenation dictionary

    Returns:
        List of WrappedLine objects
    """
    if not text:
        return []

    # Normalize whitespace
    text = normalize_whitespace(text)
    if not text:
        return []

    # Get hyphenation dictionary if enabled
    pyphen_dict = get_pyphen_dict(locale) if config.hyphenate else None

    words = text.split()
    lines: list[WrappedLine] = []
    current_line_words: list[str] = []
    current_line_width: float = 0.0

    space_width = measure_text(font, " ")

    for word in words:
        word_width = measure_text(font, word)

        # Calculate width if we add this word to current line
        if current_line_words:
            test_width = current_line_width + space_width + word_width
        else:
            test_width = word_width

        if test_width <= config.max_width:
            # Word fits on current line
            current_line_words.append(word)
            current_line_width = test_width
        else:
            # Word doesn't fit - try hyphenation
            hyphen_result = None
            if config.hyphenate and pyphen_dict:
                hyphen_result = find_hyphenation_point(
                    word,
                    font,
                    config.max_width,
                    current_line_width,
                    pyphen_dict,
                    config,
                )

            if hyphen_result:
                first_part, remaining = hyphen_result
                # Add first part to current line
                current_line_words.append(first_part)
                line_text = " ".join(current_line_words)
                lines.append(
                    WrappedLine(
                        text=line_text,
                        width=measure_text(font, line_text),
                        ends_with_hyphen=True,
                    )
                )
                # Start new line with remaining part
                current_line_words = [remaining]
                current_line_width = measure_text(font, remaining)
            else:
                # No hyphenation possible - finish current line and start new one
                if current_line_words:
                    line_text = " ".join(current_line_words)
                    lines.append(
                        WrappedLine(
                            text=line_text,
                            width=measure_text(font, line_text),
                            ends_with_hyphen=False,
                        )
                    )

                # Check if word alone is too wide
                if word_width > config.max_width:
                    # Force-break the word (character by character as last resort)
                    remaining_word = word
                    while remaining_word:
                        # Find how many characters fit
                        for i in range(len(remaining_word), 0, -1):
                            part = remaining_word[:i]
                            if i < len(remaining_word):
                                part_with_hyphen = part + config.hyphen_char
                            else:
                                part_with_hyphen = part
                            if measure_text(font, part_with_hyphen) <= config.max_width:
                                if i < len(remaining_word):
                                    lines.append(
                                        WrappedLine(
                                            text=part_with_hyphen,
                                            width=measure_text(font, part_with_hyphen),
                                            ends_with_hyphen=True,
                                        )
                                    )
                                    remaining_word = remaining_word[i:]
                                else:
                                    # Last piece - don't add to lines yet, add to current
                                    current_line_words = [part]
                                    current_line_width = measure_text(font, part)
                                    remaining_word = ""
                                break
                        else:
                            # Even a single character doesn't fit - force it
                            lines.append(
                                WrappedLine(
                                    text=remaining_word[0],
                                    width=measure_text(font, remaining_word[0]),
                                    ends_with_hyphen=False,
                                )
                            )
                            remaining_word = remaining_word[1:]
                else:
                    current_line_words = [word]
                    current_line_width = word_width

    # Don't forget the last line
    if current_line_words:
        line_text = " ".join(current_line_words)
        lines.append(
            WrappedLine(
                text=line_text,
                width=measure_text(font, line_text),
                ends_with_hyphen=False,
            )
        )

    return lines


def calculate_text_max_width(
    image_width: int,
    text_offset_x: int,
    text_margin: int = 60,
) -> int:
    """Calculate max text width from image dimensions."""
    return image_width - text_offset_x - text_margin
