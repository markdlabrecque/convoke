"""Issue 80 synthetic evidence only. No Hermes imports, integration or tool coverage.

Run: python3 -I -B docs/evidence/hermes_tool_stop_fixture.py
Unit fact composition + one fixed Python subprocess boundary (POSIX only).
"""
from dataclasses import dataclass
import os
from pathlib import Path
from queue import Queue
import signal
import subprocess
import sys
from tempfile import TemporaryDirectory
from threading import Event, Thread
import unittest


@dataclass(frozen=True)
class Facts:
    """Illustrative proposed invariant, NOT a production ownership implementation."""

    sealed: bool = True
    joined: bool = True
    coverage: bool = True
    children: tuple = ()

    @property
    def settled(self):
        return (self.sealed and self.joined and self.coverage
                and all(child.settled for child in self.children))


def accept_ack(binding, callback_binding, prior, candidate):
    """Illustrate exact identity fencing and absorbing closure, not dispatch locking."""
    if binding != callback_binding or prior.settled:
        return prior
    return candidate


class CompositionEvidence(unittest.TestCase):
    def test_normal_completion_needs_no_artificial_stop(self):
        self.assertTrue(Facts(children=(Facts(), Facts())).settled)
        self.assertTrue(Facts(children=(Facts(),)).settled)  # next independent turn

    def test_root_return_does_not_join_child(self):
        self.assertFalse(Facts(children=(Facts(joined=False),)).settled)

    def test_parent_and_io_join_cannot_discharge_unknown(self):
        self.assertFalse(Facts(coverage=False, children=(Facts(), Facts())).settled)

    def test_signal_ack_is_not_worker_ack(self):
        self.assertFalse(Facts(joined=False).settled)

    def test_open_producer_prevents_premature_closure(self):
        self.assertFalse(Facts(sealed=False).settled)

    def test_transfer_keeps_obligation_in_original_scope(self):
        held = Facts(joined=False)
        self.assertFalse(Facts(children=(held,)).settled)
        # Routing to a parent does not remove this execution's held obligation.
        self.assertFalse(Facts(children=(Facts(children=(held,)),)).settled)

    def test_stale_callback_and_closed_generation_cannot_reopen(self):
        binding = ("owner", "epoch", "admission", 7, "invocation")
        pending = Facts(joined=False)
        stale = ("owner", "epoch", "admission", 6, "invocation")
        self.assertEqual(accept_ack(binding, stale, pending, Facts()), pending)
        self.assertEqual(accept_ack(binding, binding, Facts(), pending), Facts())


# Fixed harmless child: install a signal notification, then block on one pipe byte.
# SIGTERM acknowledges delivery but deliberately does not release the work gate.
CHILD = r'''
import os, signal
signal.signal(signal.SIGTERM, lambda *_: os.write(1, b"S"))
os.write(1, b"R")
assert os.read(0, 1) == b"X"
os.write(1, b"D")
'''
SAFETY = 10  # Deadlock/cleanup watchdog only; no elapsed-time success assertions.


def wait_event(event):
    if not event.wait(SAFETY):
        raise AssertionError("fixture gate watchdog expired")


@unittest.skipUnless(os.name == "posix", "fixed POSIX signal fixture")
class ProcessEvidence(unittest.TestCase):
    def run_leaf(self, request_stop):
        """Own every handle. Extra thread is independent work, NOT a descendant."""
        extra_started, extra_release, extra_done = Event(), Event(), Event()
        messages = Queue()
        reader_done = Event()
        proc = reader = extra = None

        def independent_work():
            extra_started.set()
            try:
                wait_event(extra_release)
            finally:
                extra_done.set()

        def drain():
            try:
                while byte := os.read(proc.stdout.fileno(), 1):
                    messages.put(byte)
            except BaseException as error:
                messages.put(error)
            finally:
                reader_done.set()

        def expect(marker):
            self.assertEqual(messages.get(timeout=SAFETY), marker)

        with TemporaryDirectory(prefix="convoke80-") as home:
            try:
                extra = Thread(target=independent_work)
                extra.start()
                wait_event(extra_started)
                proc = subprocess.Popen(
                    [str(Path(sys.executable).resolve()), "-I", "-S", "-B", "-c", CHILD],
                    shell=False, cwd=home,
                    env={"HOME": home, "LANG": "C", "LC_ALL": "C"},
                    stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL, close_fds=True,
                )
                reader = Thread(target=drain)
                reader.start()
                expect(b"R")
                # Popen/dispatch already returned, but the exact process is held.
                # poll() is an observation, not a wait/retry or cessation bound.
                self.assertIsNone(proc.poll())
                if request_stop:
                    proc.send_signal(signal.SIGTERM)
                    expect(b"S")
                    self.assertIsNone(proc.poll())
                    self.assertFalse(reader_done.is_set())
                proc.stdin.write(b"X")
                proc.stdin.flush()
                expect(b"D")
                self.assertEqual(proc.wait(timeout=SAFETY), 0)
                wait_event(reader_done)
                reader.join(timeout=SAFETY)
                self.assertFalse(reader.is_alive())
                # Even actual process + I/O joins do not join independent work.
                self.assertFalse(extra_done.is_set())
                extra_release.set()
                extra.join(timeout=SAFETY)
                self.assertFalse(extra.is_alive())
                self.assertTrue(extra_done.is_set())
            finally:
                extra_release.set()
                # Kill only the exact unreaped Popen child on failure, never a group/name.
                try:
                    if proc is not None:
                        if proc.poll() is None:
                            proc.kill()
                        proc.wait(timeout=SAFETY)
                finally:
                    for thread in (reader, extra):
                        if thread is not None:
                            thread.join(timeout=SAFETY)
                    if proc is not None:
                        for stream in (proc.stdin, proc.stdout):
                            if stream is not None:
                                stream.close()
                if any(t is not None and t.is_alive() for t in (reader, extra)):
                    raise RuntimeError("fixture thread cleanup failed")

    def test_ordinary_leaf_completion_is_local_not_global(self):
        self.run_leaf(False)

    def test_signal_notification_is_not_exit_or_global_settlement(self):
        self.run_leaf(True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
