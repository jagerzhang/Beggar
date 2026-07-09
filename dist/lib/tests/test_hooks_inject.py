"""Unit tests for hooks_inject.py — settings.json hook injection."""
import json
import os
import sys
import tempfile
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))


def _run_action(action, **env_vars):
    """Run hooks_inject.py with given action and env vars."""
    import subprocess
    script = os.path.join(os.path.dirname(__file__), '..', 'hooks_inject.py')
    env = os.environ.copy()
    env.update(env_vars)
    env['ACTION'] = action
    result = subprocess.run(
        [sys.executable, script],
        capture_output=True, text=True, env=env
    )
    return result.stdout.strip(), result.stderr.strip(), result.returncode


class TestActionCheck:
    """Test the check action — check if superpowers plugin is enabled."""

    def test_plugin_enabled(self, tmp_settings_file):
        # Enable plugin
        with open(tmp_settings_file, 'w') as f:
            json.dump({"enabledPlugins": {"superpowers@codebuddy-plugins-official": True}}, f)
        stdout, _, code = _run_action('check', SETTINGS_FILE=tmp_settings_file)
        assert stdout == 'true'

    def test_plugin_disabled(self, tmp_settings_file):
        with open(tmp_settings_file, 'w') as f:
            json.dump({"enabledPlugins": {"superpowers@codebuddy-plugins-official": False}}, f)
        stdout, _, code = _run_action('check', SETTINGS_FILE=tmp_settings_file)
        assert stdout == 'false'

    def test_no_plugins_key(self, tmp_settings_file):
        with open(tmp_settings_file, 'w') as f:
            json.dump({}, f)
        stdout, _, code = _run_action('check', SETTINGS_FILE=tmp_settings_file)
        assert stdout == 'false'

    def test_file_not_found(self):
        stdout, _, code = _run_action('check', SETTINGS_FILE='/tmp/nonexistent_test_file.json')
        assert stdout == 'false'


class TestActionInjectSuperpowers:
    """Test inject_superpowers action."""

    def test_inject_into_empty_settings(self, tmp_settings_file):
        with open(tmp_settings_file, 'w') as f:
            json.dump({}, f)
        stdout, _, code = _run_action('inject_superpowers', SETTINGS_FILE=tmp_settings_file)
        assert stdout == 'injected'
        with open(tmp_settings_file) as f:
            data = json.load(f)
        assert data['enabledPlugins']['superpowers@codebuddy-plugins-official'] is True

    def test_inject_preserves_existing_plugins(self, tmp_settings_file):
        with open(tmp_settings_file, 'w') as f:
            json.dump({"enabledPlugins": {"other-plugin": True}, "otherKey": "value"}, f)
        stdout, _, code = _run_action('inject_superpowers', SETTINGS_FILE=tmp_settings_file)
        assert stdout == 'injected'
        with open(tmp_settings_file) as f:
            data = json.load(f)
        assert data['enabledPlugins']['superpowers@codebuddy-plugins-official'] is True
        assert data['enabledPlugins']['other-plugin'] is True
        assert data['otherKey'] == 'value'

    def test_inject_creates_file(self):
        with tempfile.NamedTemporaryFile(suffix='.json', delete=True) as f:
            path = f.name
        # File doesn't exist
        stdout, _, code = _run_action('inject_superpowers', SETTINGS_FILE=path)
        assert stdout == 'injected'
        with open(path) as f:
            data = json.load(f)
        assert data['enabledPlugins']['superpowers@codebuddy-plugins-official'] is True
        os.unlink(path)


class TestActionInjectHooks:
    """Test inject_hooks action."""

    def test_inject_hooks_project_mode(self, tmp_settings_file):
        """Inject hooks in project mode (BEGGAR_GLOBAL=0)."""
        with open(tmp_settings_file, 'w') as f:
            json.dump({}, f)
        stdout, _, code = _run_action('inject_hooks',
                                       SETTINGS_FILE=tmp_settings_file,
                                       BEGGAR_GLOBAL='0')
        # Should output at least 'injected' (and possibly rtk_not_found)
        lines = stdout.split('\n')
        assert 'injected' in lines or 'no_change' in lines

        with open(tmp_settings_file) as f:
            data = json.load(f)
        hooks = data.get('hooks', {})

        # Notification hooks should be present
        assert 'Notification' in hooks
        notif_matchers = hooks['Notification']
        assert any(m.get('matcher') == 'permission_prompt' for m in notif_matchers)

        # PreToolUse hooks should be present
        assert 'PreToolUse' in hooks

        # SubagentStop hooks should be present
        assert 'SubagentStop' in hooks

    def test_inject_hooks_idempotent(self, tmp_settings_file):
        """Injecting hooks twice should not duplicate."""
        with open(tmp_settings_file, 'w') as f:
            json.dump({}, f)
        # First injection
        _run_action('inject_hooks', SETTINGS_FILE=tmp_settings_file, BEGGAR_GLOBAL='0')
        # Second injection
        stdout, _, code = _run_action('inject_hooks',
                                       SETTINGS_FILE=tmp_settings_file,
                                       BEGGAR_GLOBAL='0')
        lines = stdout.split('\n')
        assert 'no_change' in lines

        with open(tmp_settings_file) as f:
            data = json.load(f)
        hooks = data['hooks']
        # Count beggar hooks in Notification
        notif_count = sum(
            1 for m in hooks.get('Notification', [])
            for h in m.get('hooks', [])
            if 'beggar-notify-hook.py' in h.get('command', '')
        )
        assert notif_count == 2  # permission_prompt + idle_prompt

    def test_inject_hooks_global_mode(self, tmp_settings_file):
        """Inject hooks in global mode — hook path should use $HOME."""
        with open(tmp_settings_file, 'w') as f:
            json.dump({}, f)
        _run_action('inject_hooks', SETTINGS_FILE=tmp_settings_file, BEGGAR_GLOBAL='1')
        with open(tmp_settings_file) as f:
            data = json.load(f)
        hooks = data['hooks']
        for m in hooks.get('Notification', []):
            for h in m.get('hooks', []):
                cmd = h.get('command', '')
                if 'beggar-notify-hook.py' in cmd:
                    assert '${HOME}' in cmd or '$HOME' in cmd


class TestActionRemoveHooks:
    """Test remove_hooks action."""

    def test_remove_all_beggar_hooks(self, tmp_settings_file):
        """Inject then remove — should leave no beggar hooks."""
        with open(tmp_settings_file, 'w') as f:
            json.dump({}, f)
        # Inject
        _run_action('inject_hooks', SETTINGS_FILE=tmp_settings_file, BEGGAR_GLOBAL='0')
        # Remove
        stdout, _, code = _run_action('remove_hooks', SETTINGS_FILE=tmp_settings_file)
        assert stdout == 'removed'

        with open(tmp_settings_file) as f:
            data = json.load(f)
        # hooks key should be gone or empty
        hooks = data.get('hooks', {})
        for event_name, matchers in hooks.items():
            for m in (matchers if isinstance(matchers, list) else []):
                for h in m.get('hooks', []):
                    assert 'beggar-notify-hook.py' not in h.get('command', '')

    def test_remove_preserves_non_beggar_hooks(self, tmp_settings_file):
        """Non-beggar hooks should be preserved."""
        with open(tmp_settings_file, 'w') as f:
            json.dump({
                "hooks": {
                    "PreToolUse": [
                        {"matcher": "Bash", "hooks": [{"type": "command", "command": "other-hook.sh"}]}
                    ]
                }
            }, f)
        _run_action('remove_hooks', SETTINGS_FILE=tmp_settings_file)
        with open(tmp_settings_file) as f:
            data = json.load(f)
        hooks = data.get('hooks', {})
        # The non-beggar hook should still be there
        pretooluse = hooks.get('PreToolUse', [])
        assert len(pretooluse) == 1
        assert pretooluse[0]['hooks'][0]['command'] == 'other-hook.sh'


class TestActionCheckHooksEnabled:
    """Test check_hooks_enabled action."""

    def test_hooks_present(self, tmp_settings_file):
        with open(tmp_settings_file, 'w') as f:
            json.dump({}, f)
        _run_action('inject_hooks', SETTINGS_FILE=tmp_settings_file, BEGGAR_GLOBAL='0')
        stdout, _, _ = _run_action('check_hooks_enabled', SETTINGS_FILE=tmp_settings_file)
        assert stdout == 'true'

    def test_hooks_absent(self, tmp_settings_file):
        with open(tmp_settings_file, 'w') as f:
            json.dump({}, f)
        stdout, _, _ = _run_action('check_hooks_enabled', SETTINGS_FILE=tmp_settings_file)
        assert stdout == 'false'


class TestActionFixHooks:
    """Test fix_hooks action — detect and fix broken hook paths."""

    def test_no_fix_needed(self, tmp_settings_file):
        """Already correct paths — should report no_fix_needed."""
        with open(tmp_settings_file, 'w') as f:
            json.dump({}, f)
        _run_action('inject_hooks', SETTINGS_FILE=tmp_settings_file, BEGGAR_GLOBAL='0')
        stdout, _, _ = _run_action('fix_hooks', SETTINGS_FILE=tmp_settings_file, BEGGAR_GLOBAL='0')
        assert stdout == 'no_fix_needed'

    def test_fix_broken_path(self, tmp_settings_file):
        """Fix old broken path ($CODEBUDDY_PROJECT_DIR) in global mode → $HOME."""
        with open(tmp_settings_file, 'w') as f:
            json.dump({
                "hooks": {
                    "Notification": [{
                        "matcher": "permission_prompt",
                        "hooks": [{
                            "type": "command",
                            "command": "python3 $CODEBUDDY_PROJECT_DIR/.codebuddy/hooks/beggar-notify-hook.py",
                            "timeout": 10
                        }]
                    }]
                }
            }, f)
        # Use global mode so fix target is $HOME (different from $CODEBUDDY_PROJECT_DIR)
        stdout, _, _ = _run_action('fix_hooks', SETTINGS_FILE=tmp_settings_file, BEGGAR_GLOBAL='1')
        assert stdout == 'fixed'
        with open(tmp_settings_file) as f:
            data = json.load(f)
        cmd = data['hooks']['Notification'][0]['hooks'][0]['command']
        assert '$CODEBUDDY_PROJECT_DIR' not in cmd
        assert '$HOME' in cmd


class TestAtomicSave:
    """Test that _save_settings uses atomic write (temp + rename)."""

    def test_save_produces_valid_json(self, tmp_settings_file):
        _run_action('inject_superpowers', SETTINGS_FILE=tmp_settings_file)
        with open(tmp_settings_file) as f:
            data = json.load(f)
        assert isinstance(data, dict)
        # No temp files left behind
        d = os.path.dirname(tmp_settings_file)
        temp_files = [f for f in os.listdir(d) if f.startswith('.') and f.endswith('.tmp')]
        assert len(temp_files) == 0
