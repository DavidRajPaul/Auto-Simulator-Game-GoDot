"""Keeps faces and hands intact when process_people.py shrinks a character.

Nov 20 owner report ("why is the face and the hand of the green saree lady like this"): the old
pipeline simplified the whole merged character with one ratio (gltf-transform simplify), so the
3,200-triangle budget went mostly to the saree and the hair, the face collapsed (nose pushed
sideways) and the fingers became spikes. It also sized atlas tiles by surface area and then halved
the atlas, so a face got about 64 pixels.

Here every vertex gets a region (body, face, hands, hair). The simplifier runs region by region
with the other regions locked, so each one has its own triangle budget, and attributes (UV,
normal) count in the error so the eyes and lips keep their texture mapping. Atlas tiles are
weighted by region too, and each texture is cropped to the part its UVs actually use.
"""
from __future__ import annotations

import numpy as np

REGION_BODY, REGION_FACE, REGION_HANDS, REGION_HAIR = 0, 1, 2, 3
HAIR_WORDS = ("hair", "haircut", "bun", "boudin", "ponytail", "braid", "jada")
FACE_WORDS = ("head", "face", "eye", "pupil", "iris", "mouth", "lip", "brow", "nose", "bindi", "ear")
# Triangles the face (head skin, eyes, mouth) and both hands may keep, on top of the body budget.
FACE_TRIS = 1300
HANDS_TRIS = 700
HAIR_TRIS = 1100
# Atlas tile weight per region (surface share is multiplied by this).
TILE_WEIGHT = {REGION_BODY: 1.0, REGION_FACE: 10.0, REGION_HANDS: 3.0, REGION_HAIR: 0.8}
FACE_TILE_MIN = 256


def vertex_regions(part: dict, keep: list[str]) -> np.ndarray:
    """Region per vertex of one extracted part (needs J/W in kept-bone indices and the label)."""
    label = part["label"]
    n = len(part["pos"])
    mat = part.get("mat", {})
    alpha = mat.get("alphaMode", "OPAQUE") in ("MASK", "BLEND")
    J, W = part["J"], part["W"]

    def weight_of(bones: tuple[str, ...]) -> np.ndarray:
        ids = [keep.index(b) for b in bones]
        return (np.isin(J, ids) * W).sum(1)

    head_w = weight_of(("Head",))
    hand_w = weight_of(("LeftHand", "RightHand"))
    out = np.full(n, REGION_BODY, np.int8)
    if any(w in label for w in HAIR_WORDS) or (alpha and head_w.mean() > 0.4):
        out[:] = REGION_HAIR
        return out
    if any(w in label for w in FACE_WORDS) and head_w.mean() > 0.3:
        out[:] = REGION_FACE
        return out
    out[head_w >= 0.5] = REGION_FACE
    out[hand_w >= 0.35] = REGION_HANDS
    return out


def weld(pos, nrm, uv, J, W, region, idx):
    """Merge vertices that are identical in position, UV and normal (the source splits every face)."""
    key = np.c_[np.round(pos, 5), np.round(uv, 5), np.round(nrm, 3)]
    _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inverse = inverse.reshape(-1)
    return (pos[first], nrm[first], uv[first], J[first], W[first], region[first], inverse[idx])


def _meshopt():
    """meshopt_simplifyWithAttributes with its real C signature. The PyPI wrapper (0.2.30a0) sets
    no argtypes, so its size_t arguments go through as 32-bit ints and the call crashes."""
    import ctypes

    from meshoptimizer._loader import lib
    f = lib.meshopt_simplifyWithAttributes
    P = ctypes.POINTER
    f.argtypes = [P(ctypes.c_uint), P(ctypes.c_uint), ctypes.c_size_t, P(ctypes.c_float), ctypes.c_size_t,
                  ctypes.c_size_t, P(ctypes.c_float), ctypes.c_size_t, P(ctypes.c_float), ctypes.c_size_t,
                  P(ctypes.c_ubyte), ctypes.c_size_t, ctypes.c_float, ctypes.c_uint, P(ctypes.c_float)]
    f.restype = ctypes.c_size_t
    return f


def _simplify_pass(pos, attrs, weights, idx, lock, target_tris):
    import ctypes
    f = _meshopt()
    P = ctypes.POINTER
    idx32 = np.ascontiguousarray(idx, np.uint32)
    p32 = np.ascontiguousarray(pos, np.float32)
    a32 = np.ascontiguousarray(attrs, np.float32)
    w32 = np.ascontiguousarray(weights, np.float32)
    l8 = np.ascontiguousarray(lock, np.uint8)
    dest = np.zeros(len(idx32), np.uint32)
    err = ctypes.c_float(0.0)
    n = f(dest.ctypes.data_as(P(ctypes.c_uint)), idx32.ctypes.data_as(P(ctypes.c_uint)), len(idx32),
          p32.ctypes.data_as(P(ctypes.c_float)), len(p32), 12, a32.ctypes.data_as(P(ctypes.c_float)),
          a32.shape[1] * 4, w32.ctypes.data_as(P(ctypes.c_float)), len(w32), l8.ctypes.data_as(P(ctypes.c_ubyte)),
          int(target_tris) * 3, 1.0, 0, ctypes.byref(err))
    return dest[:n].astype(np.int64)


def simplify_by_region(pos, nrm, uv, J, W, region, idx, body_budget: int,
                       face_budget: int = FACE_TRIS, hands_budget: int = HANDS_TRIS):
    """Simplifies body+hair to body_budget, then face and hands to their own budgets, each pass
    with the other regions locked. Returns compacted arrays."""
    pos, nrm, uv, J, W, region, idx = weld(pos, nrm, uv, J, W, region, idx)
    # UVs weigh most (texture seams on the eyes and lips), normals keep the silhouette of fingers.
    attrs = np.c_[uv, nrm]
    weights = [1.0, 1.0, 0.25, 0.25, 0.25]

    def tri_regions(ix: np.ndarray) -> np.ndarray:
        # A triangle belongs to the highest-priority region among its corners (face/hands win).
        r = region[ix.reshape(-1, 3)]
        out = np.full(len(r), REGION_BODY)
        out[(r == REGION_HAIR).any(1)] = REGION_HAIR
        out[(r == REGION_HANDS).any(1)] = REGION_HANDS
        out[(r == REGION_FACE).any(1)] = REGION_FACE
        return out

    # Hair has its own share of the budget: strand-soup hair used to take most of it and leave
    # the clothes a few hundred triangles.
    hair_budget = int(min(HAIR_TRIS, max(900, body_budget * 0.3)))
    plan = [((REGION_BODY,), body_budget - hair_budget), ((REGION_HAIR,), hair_budget),
            ((REGION_FACE,), face_budget), ((REGION_HANDS,), hands_budget)]
    for regions, budget in plan:
        tr = tri_regions(idx)
        mine = np.isin(tr, regions)
        have = int(mine.sum())
        if have <= budget:
            continue
        lock = ~np.isin(region, regions)
        target = len(tr) - have + budget
        idx = _simplify_pass(pos, attrs, weights, idx, lock, target)
    used = np.unique(idx)
    remap = np.full(len(pos), -1, np.int64)
    remap[used] = np.arange(len(used))
    return pos[used], nrm[used], uv[used], J[used], W[used], region[used], remap[idx]


def region_counts(region: np.ndarray, idx: np.ndarray) -> dict[str, int]:
    r = region[idx.reshape(-1, 3)].max(1)
    names = {REGION_BODY: "body", REGION_FACE: "face", REGION_HANDS: "hands", REGION_HAIR: "hair"}
    return {names[k]: int((r == k).sum()) for k in names}


def split_by_region(parts: list[dict]) -> list[dict]:
    """Splits each part into its face, hands and other triangles, so the atlas can give a face or
    a pair of hands that share one skin texture with the body (Wife Final, Female test) their own
    sharper tile. Vertices on a region border are duplicated (same position, same texture colour)."""
    out = []
    for p in parts:
        r = p["region"][p["idx"].reshape(-1, 3)]
        tri = np.where((r == REGION_FACE).any(1), REGION_FACE,
                       np.where((r == REGION_HANDS).any(1), REGION_HANDS, REGION_BODY))
        groups = [g for g in (REGION_FACE, REGION_HANDS, REGION_BODY) if (tri == g).any()]
        if len(groups) <= 1:
            p["tile_region"] = groups[0] if groups else REGION_BODY
            out.append(p)
            continue
        for g in groups:
            t = p["idx"].reshape(-1, 3)[tri == g]
            used = np.unique(t)
            remap = np.full(len(p["pos"]), -1, np.int64)
            remap[used] = np.arange(len(used))
            q = {k: (v[used] if isinstance(v, np.ndarray) and len(v) == len(p["pos"]) else v) for k, v in p.items()}
            q["idx"] = remap[t].reshape(-1)
            q["tile_region"] = g
            out.append(q)
    return out
