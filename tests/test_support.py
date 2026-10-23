"""Offline checks of release metadata and live-test cleanup; no desktop I/O."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

import live_support as live
import live_player
import live_shell

spec = importlib.util.spec_from_file_location("check_versions", Path(__file__).resolve().parents[1] / "scripts/check_versions.py")
versions = importlib.util.module_from_spec(spec)
spec.loader.exec_module(versions)


class SupportTests(unittest.TestCase):
    def test_check_script_uses_its_fresh_native_binary_despite_caller_overrides(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            shutil.copy(Path(__file__).resolve().parents[1] / 'scripts/check.sh', root / 'scripts/check.sh')
            fake = root / 'tools'
            fake.mkdir()
            programs = {
                'rustc': 'print("host: test-native-host")\n',
                'cargo': '''import pathlib, sys
args = sys.argv[1:]
if args[0] != 'fmt':
    assert args[args.index('--target') + 1] == 'test-native-host', args
    assert pathlib.Path(args[args.index('--target-dir') + 1]) == pathlib.Path.cwd() / 'target', args
if args[0] == 'build':
    binary = pathlib.Path(args[args.index('--target-dir') + 1]) / 'test-native-host/debug/omarchy-volumio'
    binary.parent.mkdir(parents=True)
    binary.write_text('fresh build')
''',
                'python3': '''import os, pathlib, sys
if sys.argv[1:] == ['tests/test_bridge.py']:
    binary = pathlib.Path(os.environ['VOLUMIO_BINARY'])
    assert binary == pathlib.Path.cwd() / 'target/test-native-host/debug/omarchy-volumio', binary
    assert binary.read_text() == 'fresh build'
    # Stop before QML tools: this test exercises build/test selection only.
    sys.exit(73)
''',
            }
            for name, source in programs.items():
                program = fake / name
                program.write_text('#!' + sys.executable + '\n' + source)
                program.chmod(0o755)
            env = dict(os.environ, PATH=str(fake) + os.pathsep + os.environ['PATH'],
                       CARGO_BUILD_TARGET='wrong-target', CARGO_TARGET_DIR=str(root / 'wrong-dir'),
                       VOLUMIO_BINARY=str(root / 'stale-binary'))
            result = subprocess.run(['bash', str(root / 'scripts/check.sh')], cwd='/tmp', env=env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 73, result.stdout + result.stderr)
            self.assertFalse((root / 'wrong-dir').exists())

    def test_versions_reject_each_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for manifest, cargo, lock, valid in [("0.3.0", "0.3.0", "0.3.0", True),
                                                ("0.1.0", "0.3.0", "0.3.0", False),
                                                ("0.3.0", "0.1.0", "0.3.0", False),
                                                ("0.3.0", "0.3.0", "0.1.0", False)]:
                (root / "manifest.json").write_text(json.dumps({"version": manifest}))
                (root / "Cargo.toml").write_text(f'[package]\nname="omarchy-volumio"\nversion="{cargo}"\n')
                (root / "Cargo.lock").write_text(f'[[package]]\nname="omarchy-volumio"\nversion="{lock}"\n')
                if valid:
                    self.assertEqual(versions.check_versions(root), "0.3.0")
                else:
                    with self.assertRaises(ValueError):
                        versions.check_versions(root)

    def test_subprocess_calls_are_bounded(self):
        with patch.object(live.subprocess, 'run') as run:
            live.call('shell', 'listShellConfig')
            self.assertEqual(run.call_args.kwargs['timeout'], 5)
            self.assertTrue(run.call_args.kwargs['check'])

    def test_restore_disabled_or_moved_plugin_while_player_offline(self):
        saved = live.Settings('right', 2, 'http://offline.local', 'scope')
        for found, expected in [([], ('plugin', 'enable')), ([('left', 0, {})], ('bar', 'move'))]:
            with self.subTest(found=found), patch.object(live, 'entries', return_value=found), \
                    patch.object(live, 'capture_settings', return_value=saved), \
                    patch.object(live, 'status', return_value={'online': False, 'address': saved.address + '/', 'iconMode': 'scope'}), \
                    patch.object(live.subprocess, 'run') as run:
                live.restore_settings(saved)
                calls = [args.args[0] for args in run.call_args_list]
                self.assertEqual(calls[0][1:3], expected)
                self.assertIn('--index', calls[0])
                self.assertEqual(calls[-2][-2:], ('address', saved.address))
                self.assertEqual(calls[-1][-2:], ('barIcon', 'scope'))
                self.assertTrue(all(args.kwargs['timeout'] == 5 for args in run.call_args_list))

    def test_restore_attempts_independent_settings_after_timeout_without_replay(self):
        saved = live.Settings('right', 2, 'http://offline.local', 'scope')
        with patch.object(live, 'entries', return_value=[('right', 2, {})]), \
                patch.object(live.subprocess, 'run', side_effect=[subprocess.TimeoutExpired('address', 5), Mock(stdout='')]) as run:
            with self.assertRaisesRegex(RuntimeError, 'restore plugin settings'):
                live.restore_settings(saved)
            self.assertEqual(run.call_count, 2)
            self.assertEqual(run.call_args_list[1].args[0][-2:], ('barIcon', 'scope'))

    def test_shell_failure_restores_settings_and_closes_fixture(self):
        saved = live.Settings('right', 2, 'http://offline.local', 'scope')
        with patch('sys.argv', ['live_shell.py', '--run']), \
                patch.object(live_shell, 'capture_settings', return_value=saved), \
                patch.object(live_shell, 'Player') as player, \
                patch.object(live_shell, 'call', side_effect=RuntimeError('test failure')), \
                patch.object(live_shell, 'restore_settings') as restore:
            player.return_value.address = 'http://127.0.0.1:1234'
            with self.assertRaisesRegex(RuntimeError, 'test failure'):
                live_shell.main()
            restore.assert_called_once_with(saved)
            player.return_value.shutdown.assert_called_once()
            player.return_value.server_close.assert_called_once()

    def test_player_restore_tolerates_optional_fields_and_disabled_volume(self):
        for original in ({'status': 'pause'}, {'status': 'pause', 'seek': 'bad'},
                         {'status': 'pause', 'volume': 20, 'disableVolumeControl': True}):
            get = Mock()
            live_player.restore_player(original, get)
            get.assert_called_once_with('api/v1/commands/?cmd=pause')
        get = Mock()
        live_player.restore_player({'status': 'pause', 'seek': '53057', 'volume': '20'}, get)
        self.assertEqual([call.args[0] for call in get.call_args_list], [
            'api/v1/commands/?cmd=volume&volume=20', 'api/v1/commands/?cmd=seek&position=53', 'api/v1/commands/?cmd=pause'])

    def test_player_failure_always_restores_plugin_settings(self):
        saved = live.Settings('right', 2, 'http://offline.local', 'scope')
        initial = {'online': True, 'address': saved.address, 'state': {'status': 'stop'}}
        with patch('sys.argv', ['live_player.py', '--run']), \
                patch.object(live_player, 'wait', return_value=initial), \
                patch.object(live_player, 'capture_settings', return_value=saved), \
                patch.object(live_player.urllib.request, 'build_opener') as opener, \
                patch.object(live_player, 'ipc', side_effect=subprocess.TimeoutExpired('play', 5)), \
                patch.object(live_player, 'restore_player', side_effect=RuntimeError('restoration failed')), \
                patch.object(live_player, 'restore_settings') as restore, patch('builtins.print'):
            opener.return_value.open.return_value.__enter__.return_value.read.return_value = b'{"status":"stop"}'
            with self.assertRaisesRegex(RuntimeError, 'restoration failed'):
                live_player.main()
            restore.assert_called_once_with(saved)

    def test_player_restore_attempts_other_commands_after_failure(self):
        get = Mock(side_effect=[TimeoutError('volume timed out'), b'OK'])
        with self.assertRaisesRegex(RuntimeError, 'restoration incomplete'):
            live_player.restore_player({'status': 'pause', 'volume': 20}, get)
        self.assertEqual(get.call_count, 2)
        self.assertEqual(get.call_args.args[0], 'api/v1/commands/?cmd=pause')

    def test_read_only_comparison_normalizes_missing_and_string_fields(self):
        self.assertTrue(live_player.matches_state({'status': 'stop', 'volume': None}, {'status': 'stop'}))
        self.assertTrue(live_player.matches_state({'status': 'play', 'volume': 20}, {'status': 'play', 'volume': '20'}))
        for value in (True, -1, 101, 'bad', None):
            self.assertIsNone(live_player.volume_value(value))
