"""Integration tests: real Rust executable, local HTTP server, no player needed."""
import json
import os
import queue
import subprocess
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


class Player(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self):
        super().__init__(("127.0.0.1", 0), Handler)
        self.snapshot = {"status": "stop", "title": "Été <live>", "artist": "BKS",
                         "album": "Test", "volume": 20, "albumart": "/albumart?cacheid=1"}
        self.mode = "ok"
        self.calls = []
        self.command_delay = 0
        threading.Thread(target=self.serve_forever, daemon=True).start()

    @property
    def address(self):
        return "http://127.0.0.1:%d" % self.server_port


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        player = self.server
        path = urlparse(self.path)
        if path.path.endswith("getState"):
            if player.mode == "slow":
                time.sleep(4)
            if player.mode == "http":
                self.send_error(503)
                return
            data = b"broken JSON" if player.mode == "json" else json.dumps(player.snapshot).encode()
        else:
            query = parse_qs(path.query)
            cmd = query["cmd"][0]
            player.calls.append(query)
            if player.command_delay:
                time.sleep(player.command_delay)
            if cmd in ("play", "pause"):
                player.snapshot["status"] = cmd
            if cmd == "volume":
                player.snapshot["volume"] = int(query["volume"][0])
            data = b'{}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except BrokenPipeError:
            pass


class Bridge:
    def __init__(self):
        self.process = subprocess.Popen([os.environ.get("VOLUMIO_BINARY", "target/debug/omarchy-volumio")],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, text=True, bufsize=1)
        self.events = queue.Queue()
        self.seq = 0
        self.thread = threading.Thread(target=self.read, daemon=True)
        self.thread.start()
        self.wait(lambda e: e["type"] == "ready")

    def read(self):
        for line in self.process.stdout:
            self.events.put(json.loads(line))

    def send(self, op, **fields):
        self.seq += 1
        self.process.stdin.write(json.dumps(dict(id=self.seq, op=op, **fields)) + "\n")
        self.process.stdin.flush()
        return self.seq

    def wait(self, predicate, timeout=8):
        deadline = time.monotonic() + timeout
        seen = []
        while time.monotonic() < deadline:
            try:
                event = self.events.get(timeout=max(.01, deadline - time.monotonic()))
            except queue.Empty:
                break
            seen.append(event)
            if predicate(event):
                return event
        raise AssertionError("Event absent; received: %r" % seen)

    def configure(self, address):
        self.send("configure", address=address)
        return self.wait(lambda e: e["type"] == "state")

    def close(self):
        self.process.stdin.close()
        self.process.wait(timeout=2)
        self.thread.join(timeout=1)
        stderr = self.process.stderr.read()
        self.process.stdout.close()
        self.process.stderr.close()
        if self.process.returncode:
            raise AssertionError(stderr)


class Tests(unittest.TestCase):
    def setUp(self):
        self.player = Player()
        self.bridge = Bridge()
        self.addCleanup(self.player.server_close)
        self.addCleanup(self.player.shutdown)
        self.addCleanup(self.bridge.close)

    def test_metadata_and_commands(self):
        event = self.bridge.configure(self.player.address)
        self.assertEqual(event["state"]["title"], "Été <live>")
        self.assertEqual(event["state"]["albumart"], self.player.address + "/albumart?cacheid=1")
        for op, fields in [("play", {}), ("pause", {}), ("previous", {}), ("next", {}), ("volume", {"volume": 21})]:
            request_id = self.bridge.send(op, **fields)
            self.assertTrue(self.bridge.wait(lambda e: e.get("id") == request_id)["ok"])
            self.bridge.wait(lambda e: e["type"] == "state")
        self.assertEqual([q["cmd"][0] for q in self.player.calls], ["play", "pause", "prev", "next", "volume"])
        self.assertEqual(self.player.snapshot["volume"], 21)

    def test_invalid_requests_and_disabled_volume(self):
        self.player.snapshot["disableVolumeControl"] = True
        self.bridge.configure(self.player.address)
        for op, fields in [("volume", {"volume": 10}), ("configure", {"address": "file:///tmp/no"}), ("delete", {})]:
            request_id = self.bridge.send(op, **fields)
            self.assertFalse(self.bridge.wait(lambda e: e.get("id") == request_id)["ok"])
        self.assertEqual(self.player.calls, [])
        self.bridge.process.stdin.write("not json\n")
        self.bridge.process.stdin.flush()
        self.assertFalse(self.bridge.wait(lambda e: e["type"] == "result" and e.get("id") is None)["ok"])

    def test_http_error_and_automatic_reconnection(self):
        self.bridge.configure(self.player.address)
        self.player.mode = "http"
        self.bridge.send("refresh")
        event = self.bridge.wait(lambda e: e["type"] == "connection" and e.get("error"))
        self.assertEqual(event["retrySeconds"], 2)
        self.player.mode = "ok"
        self.bridge.wait(lambda e: e["type"] == "state", timeout=5)

    def test_invalid_json(self):
        self.player.mode = "json"
        self.bridge.send("configure", address=self.player.address)
        event = self.bridge.wait(lambda e: e["type"] == "connection" and e.get("error"))
        self.assertIn("JSON", event["error"])

    def test_timeout_and_change_address_cancel_stale_response(self):
        self.player.mode = "slow"
        self.bridge.send("configure", address=self.player.address)
        self.bridge.wait(lambda e: e["type"] == "connection" and e.get("error"), timeout=5)
        other = Player()
        self.addCleanup(other.server_close)
        self.addCleanup(other.shutdown)
        other.snapshot["title"] = "NEW PLAYER"
        event = self.bridge.configure(other.address)
        self.assertEqual(event["state"]["title"], "NEW PLAYER")

    def test_timed_out_command_is_not_replayed(self):
        self.bridge.configure(self.player.address)
        self.player.command_delay = 4
        request_id = self.bridge.send("next")
        self.assertFalse(self.bridge.wait(lambda e: e.get("id") == request_id)["ok"])
        self.bridge.wait(lambda e: e["type"] == "state")
        self.assertEqual(len(self.player.calls), 1)

    def test_reconfigure_cancels_inflight_and_queued_commands(self):
        self.bridge.configure(self.player.address)
        self.player.command_delay = 1
        self.bridge.send("next")
        time.sleep(.1)
        self.bridge.send("previous")
        other = Player()
        self.addCleanup(other.server_close)
        self.addCleanup(other.shutdown)
        self.bridge.configure(other.address)
        time.sleep(1.1)
        self.assertEqual(len(self.player.calls), 1)
        self.assertEqual(other.calls, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
