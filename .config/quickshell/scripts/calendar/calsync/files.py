import contextlib
import fcntl
import os
import subprocess
import tempfile
import qsbackend
from .common import CalError




@contextlib.contextmanager
def file_lock(path):
    """one read-modify-write of a local calendar at a time (an edit and a
    delete arriving together lost one of them)"""
    fd = os.open(path + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def atomic_write_text(path, text):
    qsbackend.atomic_write(path, text)


def gpg_run(args, data, passphrase):
    return qsbackend.gpg_run(args, data, passphrase, CalError)


def write_private(path, data):
    return qsbackend.write_private(path, data, CalError)
