"""Shared pytest fixtures for beggar tests."""
import json
import os
import sys
import tempfile
import pytest

# Add dist/lib to sys.path so we can import beggar modules
LIB_DIR = os.path.join(os.path.dirname(__file__), '..')
if LIB_DIR not in sys.path:
    sys.path.insert(0, LIB_DIR)


@pytest.fixture
def tmp_settings_file():
    """Create a temporary settings.json file for hook tests."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump({"enabledPlugins": {}}, f)
        path = f.name
    yield path
    os.unlink(path)


@pytest.fixture
def tmp_personas_file():
    """Create a temporary personas.json with test themes."""
    data = {
        "_meta": {"default_theme": "test-theme"},
        "themes": {
            "test-theme": {
                "name": "测试主题",
                "name_en": "Test Theme",
                "greeting": "测试问候",
                "roles": {
                    "leader": {"name": "测试队长", "motto": "测试 motto"},
                    "architect": {"name": "测试架构师", "motto": "架构 motto"},
                    "coder-senior": {"name": "高级测试码农", "motto": "码 motto"},
                },
                "report_templates": {"daily": "测试日报模板"}
            },
            "alt-theme": {
                "name": "备选主题",
                "name_en": "Alt Theme",
                "greeting": "备选问候",
                "roles": {
                    "leader": {"name": "备选队长", "motto": "备选 motto"},
                },
                "report_templates": {}
            }
        }
    }
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(data, f)
        path = f.name
    yield path
    os.unlink(path)


@pytest.fixture
def tmp_active_persona_file():
    """Create a temporary persona-active.json path (file not created yet)."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=True) as f:
        path = f.name
    # File is deleted, just return the path
    yield path
    if os.path.exists(path):
        os.unlink(path)


@pytest.fixture
def tmp_models_file():
    """Create a temporary beggar-models.json with test data."""
    data = {
        "_meta": {"description": "test models"},
        "aliases": {
            "test-alias": "test-model-1",
            "tm1": "test-model-1",
        },
        "models": {
            "paid": {
                "testvendor": [
                    {
                        "id": "test-model-1",
                        "tier": "mid",
                        "cost": "x0.16",
                        "tags": ["general"],
                        "platform": ["cli", "ide"]
                    },
                    {
                        "id": "test-model-2",
                        "tier": "top",
                        "cost": "x2.00",
                        "tags": ["reasoning"],
                        "platform": ["cli", "ide"]
                    }
                ]
            },
            "free": [
                {
                    "id": "free-model-1",
                    "tier": "free",
                    "cost": "x0.00",
                    "tags": ["general"],
                    "platform": ["cli", "ide"]
                }
            ]
        },
        "presets": {
            "test-preset": {
                "description": "Test preset",
                "estimated_avg_cost": "x0.25",
                "platform": "both",
                "leader_model": "test-model-1",
                "config": {
                    "architect": "test-model-1",
                    "coder-senior": "test-model-2",
                    "coder-standard": "test-model-1",
                    "coder-lite": "free-model-1",
                    "reviewer": "test-model-1",
                    "reviewer-b-model": "free-model-1",
                    "tester": "free-model-1",
                    "recorder": "free-model-1"
                }
            }
        }
    }
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(data, f)
        path = f.name
    yield path
    os.unlink(path)


@pytest.fixture
def tmp_agents_dir():
    """Create a temporary agents directory with test agent .md files."""
    with tempfile.TemporaryDirectory() as d:
        agents = {
            "architect": "test-model-1",
            "coder-senior": "test-model-2",
            "coder-standard": "test-model-1",
            "coder-lite": "free-model-1",
            "reviewer": "test-model-1",
            "tester": "free-model-1",
            "recorder": "free-model-1",
        }
        for name, model in agents.items():
            path = os.path.join(d, f"{name}.md")
            with open(path, 'w') as f:
                f.write(f"---\nname: {name}\ndescription: Test agent {name}\nmodel: {model}\n---\n\n# {name}\n")
        yield d
