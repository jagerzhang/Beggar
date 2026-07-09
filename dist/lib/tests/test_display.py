"""Unit tests for display.py — CJK display width utilities."""
import sys
import os

# Add lib dir to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

# display.py now uses if __name__ == "__main__" guard,
# so we can safely import the pure functions without triggering side effects.
from display import display_width, pad_right, pad_left


class TestDisplayWidth:
    """Test the display_width function — measures terminal display width."""

    def test_ascii_string(self):
        """ASCII characters each take 1 column."""
        assert display_width("hello") == 5
        assert display_width("") == 0
        assert display_width("a") == 1

    def test_cjk_full_width(self):
        """CJK characters (Fullwidth/Wide) take 2 columns."""
        assert display_width("你好") == 4
        assert display_width("中") == 2
        assert display_width("a中") == 3  # 1 + 2

    def test_ansi_escape_codes(self):
        """ANSI color escape codes should not count toward width."""
        # \033[0;36m is cyan, \033[0m is reset
        colored = "\033[0;36mhello\033[0m"
        assert display_width(colored) == 5

    def test_mixed_cjk_ansi(self):
        """Mixed CJK + ANSI escape codes."""
        colored = "\033[0;36m你好\033[0m"
        assert display_width(colored) == 4

    def test_mixed_ascii_cjk(self):
        """Mixed ASCII and CJK string."""
        assert display_width("hello世界") == 9  # 5 + 4

    def test_half_width_katakana(self):
        """Half-width katakana should be 1 column (Ambiguous)."""
        # Half-width katakana ﾃ (U+FF83) is 'H' (Halfwidth) → 1 column
        assert display_width("ﾃ") == 1


class TestPadRight:
    """Test pad_right function — right-pads string to target width."""

    def test_ascii_padding(self):
        result = pad_right("hi", 10)
        assert len(result) == 10
        assert result == "hi        "

    def test_cjk_padding(self):
        """CJK chars take 2 columns, so padding should account for that."""
        result = pad_right("你好", 10)
        # "你好" is 4 columns wide, need 6 spaces
        assert display_width(result) == 10
        assert result == "你好      "

    def test_no_padding_needed(self):
        """String already at target width."""
        result = pad_right("hello", 5)
        assert result == "hello"

    def test_string_longer_than_width(self):
        """String longer than target — no truncation, no negative padding."""
        result = pad_right("hello world", 5)
        assert result == "hello world"


class TestPadLeft:
    """Test pad_left function — left-pads string to target width."""

    def test_ascii_padding(self):
        result = pad_left("hi", 10)
        assert len(result) == 10
        assert result == "        hi"

    def test_cjk_padding(self):
        result = pad_left("你好", 10)
        assert display_width(result) == 10
        assert result == "      你好"

    def test_no_padding_needed(self):
        result = pad_left("hello", 5)
        assert result == "hello"
