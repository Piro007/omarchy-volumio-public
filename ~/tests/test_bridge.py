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
        self.library = {}
        self.library_failures = set()
        self.library_calls = []
        self.activations = []
        self.activation_delay = 0
        self.playlists = []
        self.playlist_mode = "ok"
        self.command_started = threading.Event()
        self.state_started = threading.Event()
        self.state_gate = None
        self.state_calls = []
        self.apply_delay = 0
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
            player.state_calls.append(time.monotonic())
            gate = player.state_gate
            if gate is not None:
                player.state_gate = None
                stale = json.dumps(player.snapshot).encode()
                player.state_started.set()
                gate.wait(3)
                self.respond(stale)
                return
            if player.mode == "slow":
                time.sleep(4)
            if player.mode == "http":
                self.send_error(503)
                return
            data = b"broken JSON" if player.mode == "json" else json.dumps(player.snapshot).encode()
        elif path.path == "/api/v1/listplaylists":
            if player.playlist_mode == "http":
                self.send_error(503)
                return
            data = b"broken JSON" if player.playlist_mode == "json" else json.dumps(player.playlists).encode()
        elif path.path == "/api/v1/browse":
            query = parse_qs(path.query)
            uri = query["uri"][0]
            offset = int(query["offset"][0])
            player.library_calls.append((uri, offset))
            if (uri, offset) in player.library_failures:
                self.send_error(503)
                return
            items = player.library.get(uri, [])
            # Return small pages with a total count to exercise pagination.
            limit = min(2, int(query["limit"][0]))
            data = json.dumps({"navigation": {"lists": [{
                "items": items[offset:offset + limit], "count": len(items)
            }]}}).encode()
        else:
            query = parse_qs(path.query)
            cmd = query["cmd"][0]
            player.calls.append(query)
            player.command_started.set()
            if player.command_delay:
                time.sleep(player.command_delay)
            def apply():
                if cmd in ("play", "pause"):
                    player.snapshot["status"] = cmd
                if cmd == "volume":
                    player.snapshot["volume"] = int(query["volume"][0])
            if player.apply_delay:
                threading.Timer(player.apply_delay, apply).start()
            else:
                apply()
            data = b'{}'
        self.respond(data)

    def do_POST(self):
        if self.path != "/api/v1/replaceAndPlay":
            self.send_error(404)
            return
        player = self.server
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        # Capture the lookups already completed when the queue change arrives.
        player.activations.append((body, list(player.library_calls)))
        if player.activation_delay:
            time.sleep(player.activation_delay)
        self.respond(b'{}')

    def respond(self, data):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
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

    @staticmethod
    def track(storage, name):
        return {"uri": "music-library/%s/%s.flac" % (storage, name),
                "service": "mpd", "type": "song", "title": name}

    def test_commands_preempt_slow_state_and_discard_its_response(self):
        self.bridge.configure(self.player.address)
        for op, fields in (("play", {}), ("volume", {"volume": 31}), ("pause", {})):
            with self.subTest(op=op):
                gate = threading.Event()
                self.player.state_gate = gate
                self.player.state_started.clear()
                self.player.command_started.clear()
                self.bridge.send("refresh")
                self.assertTrue(self.player.state_started.wait(1))
                try:
                    request_id = self.bridge.send(op, **fields)
                    # The read is still held: dispatch must not depend on it finishing.
                    self.assertTrue(self.player.command_started.wait(.8))
                    self.assertTrue(self.bridge.wait(lambda e: e.get("id") == request_id)["ok"])
                    state = self.bridge.wait(lambda e: e["type"] == "state")["state"]
                    self.assertEqual(state["status"], self.player.snapshot["status"])
                    self.assertEqual(state["volume"], self.player.snapshot["volume"])
                finally:
                    gate.set()
                # Releasing the obsolete response must not revert the state.
                state = self.bridge.wait(lambda e: e["type"] == "state")["state"]
                self.assertEqual(state["status"], self.player.snapshot["status"])
                self.assertEqual(state["volume"], self.player.snapshot["volume"])
        self.assertEqual(len(self.player.calls), 3)

    def test_delayed_state_is_confirmed_quickly_then_polling_slows(self):
        self.bridge.configure(self.player.address)
        self.player.apply_delay = .3
        started = time.monotonic()
        request_id = self.bridge.send("play")
        self.assertTrue(self.bridge.wait(lambda e: e.get("id") == request_id)["ok"])
        self.bridge.wait(lambda e: e["type"] == "state" and e["state"]["status"] == "play", timeout=1.5)
        self.assertLess(time.monotonic() - started, 1.5)
        # The burst is bounded even though no extra commands arrive.
        self.bridge.wait(lambda e: e["type"] == "state" and time.monotonic() - started >= 2)
        before = time.monotonic()
        self.bridge.wait(lambda e: e["type"] == "state", timeout=3)
        self.assertGreater(time.monotonic() - before, 1.5)
        self.assertLessEqual(len(self.player.state_calls), 12)
        self.assertEqual(len(self.player.calls), 1)

    def test_browse_paged_internal_and_mixed_albums(self):
        uris = ["albums://Artist/" + name for name in ("Internal", "NAS", "USB", "Mixed")]
        self.player.library = {
            "albums://": [{"uri": uri, "service": "mpd", "title": "Same title",
                            "albumart": "/albumart?album=" + str(i)}
                           for i, uri in enumerate(uris)],
            uris[0]: [self.track("INTERNAL", "one")],
            uris[1]: [self.track("NAS", "two")],
            uris[2]: [self.track("USB", "three")],
            uris[3]: [self.track("NAS", "four"), self.track("USB", "five"),
                      self.track("INTERNAL", "six")],
        }
        self.bridge.configure(self.player.address)
        request_id = self.bridge.send("browse_albums")
        albums = []
        while True:
            event = self.bridge.wait(lambda e: e.get("id") == request_id)
            self.assertEqual(event["type"], "albums", event)
            albums.extend(event["items"])
            if event["done"]:
                break
        self.assertEqual([item["uri"] for item in albums], [uris[0], uris[3]])
        self.assertEqual(albums[0]["albumart"], self.player.address + "/albumart?album=0")
        self.assertIn(("albums://", 2), self.player.library_calls)
        self.assertIn((uris[3], 2), self.player.library_calls)
        self.assertEqual(self.player.activations, [])
        self.assertEqual(self.player.calls, [])

    def test_album_activation_resolves_all_pages_before_one_queue_change(self):
        uri = "albums://Artist/Mixed"
        first = self.track("INTERNAL", "third")
        second = self.track("INTERNAL", "first")
        second["type"] = "track"
        last = self.track("INTERNAL", "second")
        self.player.library[uri] = [first, self.track("NAS", "external"), second,
                                    self.track("USB", "external"), last]
        self.bridge.configure(self.player.address)
        request_id = self.bridge.send("play_album", uri=uri)
        self.assertTrue(self.bridge.wait(lambda e: e.get("id") == request_id)["ok"])
        self.assertEqual(self.player.activations, [(
            {"item": first, "list": [first, second, last], "index": 0},
            [(uri, 0), (uri, 2), (uri, 4)],
        )])
        self.assertEqual(self.player.calls, [])  # No separate clear/play command.

    def test_failed_album_lookup_does_not_change_queue(self):
        uri = "albums://Artist/Album"
        self.bridge.configure(self.player.address)
        for scenario in ("later page fails", "no internal tracks"):
            with self.subTest(scenario=scenario):
                self.player.library[uri] = [self.track("INTERNAL", "one"),
                                            self.track("NAS", "two"),
                                            self.track("INTERNAL", "three")]
                self.player.library_failures = {(uri, 2)}
                if scenario == "no internal tracks":
                    self.player.library[uri] = [self.track("USB", "external")]
                    self.player.library_failures = set()
                request_id = self.bridge.send("play_album", uri=uri)
                self.assertFalse(self.bridge.wait(lambda e: e.get("id") == request_id)["ok"])
                self.bridge.wait(lambda e: e["type"] == "state")
                self.assertEqual(self.player.activations, [])
                self.assertEqual(self.player.calls, [])

    def test_timed_out_album_activation_is_not_replayed(self):
        uri = "albums://Artist/Album"
        self.player.library[uri] = [self.track("INTERNAL", "one")]
        self.player.activation_delay = 4
        self.bridge.configure(self.player.address)
        request_id = self.bridge.send("play_album", uri=uri)
        result = self.bridge.wait(lambda e: e.get("id") == request_id)
        self.assertFalse(result["ok"])
        self.assertIn("may have changed", result["error"])
        self.bridge.wait(lambda e: e["type"] == "state")
        self.bridge.wait(lambda e: e["type"] == "state")  # One further polling cycle.
        self.assertEqual(len(self.player.activations), 1)
        self.assertEqual(self.player.library_calls, [(uri, 0)])
        self.assertEqual(self.player.calls, [])

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

    def test_lists_and_plays_saved_playlist_names(self):
        self.player.playlists = ["Quiet evening", "Été & Jazz + 100%? #1"]
        self.bridge.configure(self.player.address)
        request_id = self.bridge.send("browse_playlists")
        listing = self.bridge.wait(lambda e: e.get("id") == request_id)
        self.assertEqual(listing["type"], "playlists")
        self.assertTrue(listing["done"])
        self.assertEqual([item["name"] for item in listing["items"]], self.player.playlists)
        self.assertEqual(self.player.calls, [])
        for name in self.player.playlists:
            request_id = self.bridge.send("play_playlist", name=name)
            self.assertTrue(self.bridge.wait(lambda e: e.get("id") == request_id)["ok"])
            self.bridge.wait(lambda e: e["type"] == "state")
        self.assertEqual(self.player.calls, [{"cmd": ["playplaylist"], "name": [name]}
                                             for name in self.player.playlists])
        self.assertEqual(self.player.library_calls, [])
        self.assertEqual(self.player.activations, [])

    def test_playlist_listing_empty_and_errors_leave_controls_online(self):
        self.bridge.configure(self.player.address)
        for mode, playlists in (("ok", []), ("http", []), ("json", []), ("ok", {"error": "Bad list"})):
            with self.subTest(mode=mode, playlists=playlists):
                self.player.playlist_mode = mode
                self.player.playlists = playlists
                request_id = self.bridge.send("browse_playlists")
                event = self.bridge.wait(lambda e: e.get("id") == request_id)
                if mode == "ok" and playlists == []:
                    self.assertEqual(event["type"], "playlists")
                    self.assertEqual(event["items"], [])
                    self.assertTrue(event["done"])
                else:
                    self.assertEqual(event["type"], "library_error")
                    self.assertTrue(event["error"])
                self.bridge.send("refresh")
                self.assertTrue(self.bridge.wait(lambda e: e["type"] == "state")["online"])
                self.assertEqual(self.player.calls, [])

    def test_timed_out_playlist_is_not_replayed_and_blocks_duplicate_activation(self):
        self.bridge.configure(self.player.address)
        self.player.command_delay = 4
        request_id = self.bridge.send("play_playlist", name="Evening")
        self.assertTrue(self.player.command_started.wait(timeout=2))
        for op, fields in (("play_playlist", {"name": "Other"}),
                           ("play_album", {"uri": "albums://Artist/Album"})):
            duplicate_id = self.bridge.send(op, **fields)
            self.assertFalse(self.bridge.wait(lambda e: e.get("id") == duplicate_id)["ok"])
        result = self.bridge.wait(lambda e: e.get("id") == request_id)
        self.assertFalse(result["ok"])
        self.assertIn("may have changed", result["error"])
        self.bridge.wait(lambda e: e["type"] == "state")
        self.bridge.wait(lambda e: e["type"] == "state")
        self.assertEqual(self.player.calls, [{"cmd": ["playplaylist"], "name": ["Evening"]}])
        self.assertEqual(self.player.activations, [])

    def test_invalid_requests_and_disabled_volume(self):
        self.player.snapshot["disableVolumeControl"] = True
        self.bridge.configure(self.player.address)
        for op, fields in [("volume", {"volume": 10}), ("configure", {"address": "file:///tmp/no"}),
                           ("play_playlist", {"name": "../bad"}), ("delete", {})]:
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
