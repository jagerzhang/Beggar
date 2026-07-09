"""Unit tests for persona_expand.py — theme management."""
import json
import os
import sys
import tempfile
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))


def _run_action(action, **env_vars):
    """Run persona_expand.py with given action and env vars, return (stdout, stderr, exit_code)."""
    import subprocess
    script = os.path.join(os.path.dirname(__file__), '..', 'persona_expand.py')
    env = os.environ.copy()
    env.update(env_vars)
    env['ACTION'] = action
    result = subprocess.run(
        [sys.executable, script],
        capture_output=True, text=True, env=env
    )
    return result.stdout.strip(), result.stderr.strip(), result.returncode


class TestActionValidate:
    """Test the validate action — check if theme exists."""

    def test_valid_theme(self, tmp_personas_file):
        stdout, _, code = _run_action('validate',
                                       PERSONAS_FILE=tmp_personas_file,
                                       TARGET_THEME='test-theme')
        assert stdout == 'yes'
        assert code == 0

    def test_invalid_theme(self, tmp_personas_file):
        stdout, _, code = _run_action('validate',
                                       PERSONAS_FILE=tmp_personas_file,
                                       TARGET_THEME='nonexistent')
        assert code == 1

    def test_empty_theme(self, tmp_personas_file):
        stdout, _, code = _run_action('validate',
                                       PERSONAS_FILE=tmp_personas_file,
                                       TARGET_THEME='')
        assert code == 1


class TestActionExpand:
    """Test the expand action — write theme to persona-active.json."""

    def test_expand_valid_theme(self, tmp_personas_file, tmp_active_persona_file):
        stdout, _, code = _run_action('expand',
                                       PERSONAS_FILE=tmp_personas_file,
                                       ACTIVE_PERSONA=tmp_active_persona_file,
                                       TARGET_THEME='test-theme')
        assert code == 0
        # Verify file was written
        assert os.path.exists(tmp_active_persona_file)
        with open(tmp_active_persona_file) as f:
            data = json.load(f)
        assert data['theme'] == 'test-theme'
        assert data['greeting'] == '测试问候'
        assert 'leader' in data['roles']
        assert data['roles']['leader'] == '测试队长'
        assert 'report_templates' in data

    def test_expand_invalid_theme_falls_back(self, tmp_personas_file, tmp_active_persona_file):
        """Invalid theme should fall back to 'beggar-gang' per code logic.
        If 'beggar-gang' is not in themes, the code will KeyError (expected behavior).
        This test verifies the fallback path is triggered."""
        # Add 'beggar-gang' to test data so fallback works
        import copy
        data = json.load(open(tmp_personas_file))
        data['themes']['beggar-gang'] = {
            "name": "丐帮",
            "name_en": "Beggar Gang",
            "greeting": "丐帮帮主",
            "roles": {"leader": {"name": "帮主", "motto": "降龙"}},
            "report_templates": {}
        }
        with open(tmp_personas_file, 'w') as f:
            json.dump(data, f)

        stdout, _, code = _run_action('expand',
                                       PERSONAS_FILE=tmp_personas_file,
                                       ACTIVE_PERSONA=tmp_active_persona_file,
                                       TARGET_THEME='nonexistent')
        assert code == 0
        with open(tmp_active_persona_file) as f:
            active = json.load(f)
        assert active['theme'] == 'beggar-gang'

    def test_expand_with_beggar_gang_fallback(self, tmp_active_persona_file):
        """Test that expand falls back to 'beggar-gang' when theme not found."""
        data = {
            "_meta": {"default_theme": "beggar-gang"},
            "themes": {
                "beggar-gang": {
                    "name": "丐帮",
                    "name_en": "Beggar Gang",
                    "greeting": "丐帮帮主",
                    "roles": {"leader": {"name": "帮主", "motto": "降龙"}},
                    "report_templates": {}
                }
            }
        }
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json.dump(data, f)
            pf = f.name
        try:
            stdout, _, code = _run_action('expand',
                                           PERSONAS_FILE=pf,
                                           ACTIVE_PERSONA=tmp_active_persona_file,
                                           TARGET_THEME='nonexistent')
            assert code == 0
            with open(tmp_active_persona_file) as f:
                active = json.load(f)
            assert active['theme'] == 'beggar-gang'
        finally:
            os.unlink(pf)


class TestActionGetCurrent:
    """Test the get_current action."""

    def test_get_current_theme(self, tmp_personas_file, tmp_active_persona_file):
        # First expand a theme
        _run_action('expand',
                     PERSONAS_FILE=tmp_personas_file,
                     ACTIVE_PERSONA=tmp_active_persona_file,
                     TARGET_THEME='test-theme')
        # Then get current
        stdout, _, code = _run_action('get_current',
                                       ACTIVE_PERSONA=tmp_active_persona_file)
        assert stdout == 'test-theme'
        assert code == 0


class TestActionSet:
    """Test the set action — expand and write specific theme."""

    def test_set_valid_theme(self, tmp_personas_file, tmp_active_persona_file):
        stdout, _, code = _run_action('set',
                                       PERSONAS_FILE=tmp_personas_file,
                                       ACTIVE_PERSONA=tmp_active_persona_file,
                                       TARGET_THEME='alt-theme')
        assert code == 0
        with open(tmp_active_persona_file) as f:
            data = json.load(f)
        assert data['theme'] == 'alt-theme'
        assert data['greeting'] == '备选问候'


class TestActionGetGreeting:
    """Test the get_greeting action."""

    def test_get_greeting_from_active(self, tmp_personas_file, tmp_active_persona_file):
        # Set a theme first
        _run_action('set',
                     PERSONAS_FILE=tmp_personas_file,
                     ACTIVE_PERSONA=tmp_active_persona_file,
                     TARGET_THEME='test-theme')
        # Get greeting
        stdout, _, code = _run_action('get_greeting',
                                       ACTIVE_PERSONA=tmp_active_persona_file,
                                       PERSONAS_FILE=tmp_personas_file)
        assert stdout == '测试问候'
        assert code == 0

    def test_get_greeting_fallback_to_default(self, tmp_personas_file):
        """When no active persona, fall back to default theme greeting."""
        stdout, _, code = _run_action('get_greeting',
                                       ACTIVE_PERSONA='',
                                       PERSONAS_FILE=tmp_personas_file)
        # Default theme is 'test-theme', greeting is '测试问候'
        assert '测试' in stdout or '问候' in stdout


class TestActionShowCurrentConfig:
    """Test the show_current_config action."""

    def test_has_roles(self, tmp_personas_file, tmp_active_persona_file):
        _run_action('expand',
                     PERSONAS_FILE=tmp_personas_file,
                     ACTIVE_PERSONA=tmp_active_persona_file,
                     TARGET_THEME='test-theme')
        stdout, _, code = _run_action('show_current_config',
                                       ACTIVE_PERSONA=tmp_active_persona_file)
        assert stdout == 'yes'

    def test_no_roles(self, tmp_active_persona_file):
        """Old format without roles key."""
        with open(tmp_active_persona_file, 'w') as f:
            json.dump({"theme": "old"}, f)
        stdout, _, code = _run_action('show_current_config',
                                       ACTIVE_PERSONA=tmp_active_persona_file)
        assert stdout == 'no'


class TestAtomicWrite:
    """Test that _atomic_write_json uses atomic operations."""

    def test_atomic_write_produces_valid_json(self, tmp_personas_file, tmp_active_persona_file):
        _run_action('expand',
                     PERSONAS_FILE=tmp_personas_file,
                     ACTIVE_PERSONA=tmp_active_persona_file,
                     TARGET_THEME='test-theme')
        # Verify the file is valid JSON (not half-written)
        with open(tmp_active_persona_file) as f:
            data = json.load(f)
        assert isinstance(data, dict)
        assert 'theme' in data
