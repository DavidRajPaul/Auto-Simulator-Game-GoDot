"""Small glTF 2.0 reader + rig maths for the people pipeline (tools/assets/process_people.py).

Reads .gltf/.glb with external or embedded buffers, decodes accessors with numpy, evaluates node
hierarchies at rest or at an animation time, and skins meshes into world space. Only what the
people pipeline needs: no Draco, no morph targets.
"""
from __future__ import annotations

import json
import re
import struct
from pathlib import Path

import numpy as np

COMPONENT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}
NORM_DIV = {np.int8: 127.0, np.uint8: 255.0, np.int16: 32767.0, np.uint16: 65535.0}


# --- Quaternion / matrix helpers (quaternions are x, y, z, w like glTF) -------------------------

def quat_to_mat(q: np.ndarray) -> np.ndarray:
    x, y, z, w = q / np.linalg.norm(q)
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def mat_to_quat(m: np.ndarray) -> np.ndarray:
    t = np.trace(m)
    if t > 0:
        s = np.sqrt(t + 1.0) * 2
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    else:
        s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s]
    q = np.array(q)
    return q / np.linalg.norm(q)


def slerp(a: np.ndarray, b: np.ndarray, t: float) -> np.ndarray:
    d = float(np.dot(a, b))
    if d < 0:
        b = -b
        d = -d
    if d > 0.9995:
        r = a + t * (b - a)
        return r / np.linalg.norm(r)
    th = np.arccos(d)
    return (np.sin((1 - t) * th) * a + np.sin(t * th) * b) / np.sin(th)


def trs(t, r, s) -> np.ndarray:
    m = np.eye(4)
    m[:3, :3] = quat_to_mat(np.asarray(r, float)) @ np.diag(np.asarray(s, float))
    m[:3, 3] = t
    return m


def orthonormal(m3: np.ndarray) -> np.ndarray:
    """Closest rotation to a 3x3 that may carry scale/shear."""
    u, _, vt = np.linalg.svd(m3)
    r = u @ vt
    if np.linalg.det(r) < 0:
        u[:, -1] *= -1
        r = u @ vt
    return r


def arc(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Shortest rotation matrix taking direction a onto direction b."""
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    if c < -0.9999:
        axis = np.cross(a, [1.0, 0.0, 0.0])
        if np.linalg.norm(axis) < 1e-6:
            axis = np.cross(a, [0.0, 1.0, 0.0])
        axis /= np.linalg.norm(axis)
        return 2 * np.outer(axis, axis) - np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * (1.0 / (1.0 + c))


def yaw(angle: float) -> np.ndarray:
    c, s = np.cos(angle), np.sin(angle)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


# --- Canonical bone names --------------------------------------------------------------------

def canonical(name: str) -> str:
    """'mixamorig:LeftArm_010' / 'LeftArm_013' / 'LeftArm' -> 'LeftArm'."""
    n = name.split(":")[-1]
    n = re.sub(r"_\d+$", "", n)
    return n


# --- Reader ----------------------------------------------------------------------------------

class Gltf:
    def __init__(self, path: Path):
        self.path = Path(path)
        data = self.path.read_bytes()
        self.glb_bin = None
        if data[:4] == b"glTF":
            jl = struct.unpack("<I", data[12:16])[0]
            self.j = json.loads(data[20:20 + jl])
            off = 20 + jl
            if off < len(data):
                bl = struct.unpack("<I", data[off:off + 4])[0]
                self.glb_bin = data[off + 8:off + 8 + bl]
        else:
            self.j = json.loads(data)
        self._bufs: dict[int, bytes] = {}
        self.nodes = self.j.get("nodes", [])
        self.parent = [-1] * len(self.nodes)
        for i, n in enumerate(self.nodes):
            for c in n.get("children", []):
                self.parent[c] = i

    def buffer(self, i: int) -> bytes:
        if i not in self._bufs:
            b = self.j["buffers"][i]
            if "uri" in b:
                self._bufs[i] = (self.path.parent / b["uri"]).read_bytes()
            else:
                self._bufs[i] = self.glb_bin
        return self._bufs[i]

    def accessor(self, ai: int) -> np.ndarray:
        a = self.j["accessors"][ai]
        n = WIDTH[a["type"]]
        dt = np.dtype(COMPONENT[a["componentType"]]).newbyteorder("<")
        out = np.zeros((a["count"], n), dtype=np.float64)
        if "bufferView" in a:
            bv = self.j["bufferViews"][a["bufferView"]]
            data = self.buffer(bv["buffer"])
            off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
            stride = bv.get("byteStride", 0) or n * dt.itemsize
            raw = np.ndarray((a["count"], n), dtype=dt, buffer=data, offset=off, strides=(stride, dt.itemsize))
            out = raw.astype(np.float64)
            if a.get("normalized") and COMPONENT[a["componentType"]] in NORM_DIV:
                out = np.maximum(out / NORM_DIV[COMPONENT[a["componentType"]]], -1.0)
        if "sparse" in a:
            sp = a["sparse"]
            ia = sp["indices"]
            bv = self.j["bufferViews"][ia["bufferView"]]
            idt = np.dtype(COMPONENT[ia["componentType"]]).newbyteorder("<")
            idx = np.frombuffer(self.buffer(bv["buffer"]), dtype=idt, count=sp["count"],
                                offset=bv.get("byteOffset", 0) + ia.get("byteOffset", 0))
            va = sp["values"]
            bv = self.j["bufferViews"][va["bufferView"]]
            vals = np.frombuffer(self.buffer(bv["buffer"]), dtype=dt, count=sp["count"] * n,
                                 offset=bv.get("byteOffset", 0) + va.get("byteOffset", 0)).reshape(-1, n)
            out[idx.astype(int)] = vals
        return out

    def rest_local(self, i: int) -> np.ndarray:
        n = self.nodes[i]
        if "matrix" in n:
            return np.array(n["matrix"], float).reshape(4, 4).T
        return trs(n.get("translation", [0, 0, 0]), n.get("rotation", [0, 0, 0, 1]), n.get("scale", [1, 1, 1]))

    def rest_trs(self, i: int) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        n = self.nodes[i]
        if "matrix" in n:
            m = np.array(n["matrix"], float).reshape(4, 4).T
            s = np.linalg.norm(m[:3, :3], axis=0)
            return m[:3, 3].copy(), mat_to_quat(m[:3, :3] / s), s
        return (np.array(n.get("translation", [0, 0, 0]), float), np.array(n.get("rotation", [0, 0, 0, 1]), float),
                np.array(n.get("scale", [1, 1, 1]), float))

    def world(self, local: list[np.ndarray]) -> list[np.ndarray]:
        out: list[np.ndarray | None] = [None] * len(self.nodes)

        def w(i: int) -> np.ndarray:
            if out[i] is None:
                p = self.parent[i]
                out[i] = local[i] if p < 0 else w(p) @ local[i]
            return out[i]

        for i in range(len(self.nodes)):
            w(i)
        return out  # type: ignore[return-value]

    def rest_world(self) -> list[np.ndarray]:
        return self.world([self.rest_local(i) for i in range(len(self.nodes))])

    # --- animation sampling ---
    def anim_world(self, anim: int, t: float) -> list[np.ndarray]:
        tr = {i: list(self.rest_trs(i)) for i in range(len(self.nodes))}
        a = self.j["animations"][anim]
        for ch in a["channels"]:
            node = ch["target"].get("node")
            if node is None:
                continue
            path = ch["target"]["path"]
            if path == "weights":
                continue
            s = a["samplers"][ch["sampler"]]
            times = self._cached(s["input"])[:, 0]
            vals = self._cached(s["output"])
            interp = s.get("interpolation", "LINEAR")
            if interp == "CUBICSPLINE":
                vals = vals.reshape(len(times), 3, -1)[:, 1, :]
            k = int(np.searchsorted(times, t, side="right")) - 1
            if k < 0:
                v = vals[0]
            elif k >= len(times) - 1:
                v = vals[-1]
            elif interp == "STEP":
                v = vals[k]
            else:
                f = (t - times[k]) / max(times[k + 1] - times[k], 1e-9)
                v = slerp(vals[k], vals[k + 1], f) if path == "rotation" else vals[k] * (1 - f) + vals[k + 1] * f
            idx = {"translation": 0, "rotation": 1, "scale": 2}[path]
            tr[node][idx] = np.asarray(v, float)
        local = [trs(*tr[i]) for i in range(len(self.nodes))]
        return self.world(local)

    def anim_duration(self, anim: int) -> float:
        a = self.j["animations"][anim]
        return max(float(self.j["accessors"][s["input"]]["max"][0]) for s in a["samplers"])

    _cache: dict

    def _cached(self, ai: int) -> np.ndarray:
        if not hasattr(self, "_acc_cache"):
            self._acc_cache = {}
        if ai not in self._acc_cache:
            self._acc_cache[ai] = self.accessor(ai)
        return self._acc_cache[ai]
