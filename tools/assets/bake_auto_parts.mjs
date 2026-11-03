// Player auto -> the same model with damage parts tagged, for shaders/auto_paint.gdshader and
// shaders/auto_glass.gdshader (visible crash damage, Nov 3). Called by tools/assets/bake_auto_parts.py.
//
// The free model is two meshes (textured body, untextured glass) made of loose connected parts.
// Splitting them into separate meshes would add a draw call per part, so instead every vertex gets
// its part id in TEXCOORD_1.x (UV2 in Godot) and the shaders hide a broken mirror or crack the
// windshield by id:
//   0 body, 1 left mirror (housing + arm + glass), 2 right mirror, 3 windshield, 4 rear glass,
//   5 headlamp
// Model space: +Z is the front, +X the auto's left (glTF faces +Z; the game turns it round).
// Body panels are also midpoint-subdivided (shape unchanged, every attribute interpolated) so a
// dent has vertices to bend: the front cowl was 469 triangles for the whole front.
//
// Usage: node bake_auto_parts.mjs <src.glb> <out.glb>
import { NodeIO } from '@gltf-transform/core';
import { prune } from '@gltf-transform/functions';

const [, , src, out] = process.argv;
const io = new NodeIO();
const doc = await io.read(src);

const PART = { BODY: 0, MIRROR_L: 1, MIRROR_R: 2, WINDSHIELD: 3, REAR_GLASS: 4, HEADLAMP: 5 };

function nodeScale(mesh) {
	for (const node of doc.getRoot().listNodes()) {
		if (node.getMesh() === mesh) return node.getScale()[0];
	}
	return 1.0;
}

// Connected parts after welding by position (UV seams split vertices, not parts).
function components(pos, idx) {
	const n = pos.length / 3;
	const key = new Map();
	const rep = new Uint32Array(n);
	for (let i = 0; i < n; i++) {
		const k = `${Math.round(pos[i * 3] * 1e3)},${Math.round(pos[i * 3 + 1] * 1e3)},${Math.round(pos[i * 3 + 2] * 1e3)}`;
		if (!key.has(k)) key.set(k, i);
		rep[i] = key.get(k);
	}
	const parent = new Uint32Array(n).map((_, i) => i);
	const find = (a) => {
		while (parent[a] !== a) {
			parent[a] = parent[parent[a]];
			a = parent[a];
		}
		return a;
	};
	for (let t = 0; t < idx.length; t += 3) {
		const a = find(rep[idx[t]]);
		for (const v of [idx[t + 1], idx[t + 2]]) {
			const b = find(rep[v]);
			if (a !== b) parent[b] = a;
		}
	}
	const vc = new Int32Array(n);
	for (let i = 0; i < n; i++) vc[i] = find(rep[i]);
	// Per component: triangle count and bounds (in metres via `s`).
	const info = new Map();
	for (let t = 0; t < idx.length; t += 3) {
		const c = vc[idx[t]];
		if (!info.has(c)) info.set(c, { tris: 0, lo: [Infinity, Infinity, Infinity], hi: [-Infinity, -Infinity, -Infinity] });
		const e = info.get(c);
		e.tris++;
		for (let k = 0; k < 3; k++) {
			const v = idx[t + k];
			for (let a = 0; a < 3; a++) {
				e.lo[a] = Math.min(e.lo[a], pos[v * 3 + a]);
				e.hi[a] = Math.max(e.hi[a], pos[v * 3 + a]);
			}
		}
	}
	return { vc, info };
}

// Classify a component by where it sits (metres). Tuned on the shipped model; the Python wrapper
// checks the counts so a different source model fails loudly instead of tagging garbage.
function classify(isGlass, e, s) {
	const c = [0, 1, 2].map((a) => (e.lo[a] + e.hi[a]) * 0.5 * s);
	const size = [0, 1, 2].map((a) => (e.hi[a] - e.lo[a]) * s);
	const small = Math.max(...size) < 0.2;
	if (isGlass) {
		if (Math.abs(c[0]) > 0.6) return c[0] > 0 ? PART.MIRROR_L : PART.MIRROR_R;
		return c[2] > 0.5 ? PART.WINDSHIELD : PART.REAR_GLASS;
	}
	if (small && Math.abs(c[0]) > 0.5 && c[1] > 1.2 && c[2] > 0.6 && c[2] < 0.9) return c[0] > 0 ? PART.MIRROR_L : PART.MIRROR_R;
	if (Math.max(...size) < 0.25 && c[2] > 1.3 && c[1] > 0.45 && c[1] < 0.7) return PART.HEADLAMP;
	return PART.BODY;
}

// Which body components to subdivide (levels): big panels, not wheels (round, thin).
function subdivLevels(e, s) {
	const size = [0, 1, 2].map((a) => (e.hi[a] - e.lo[a]) * s);
	const c = [0, 1, 2].map((a) => (e.lo[a] + e.hi[a]) * 0.5 * s);
	const wheel = Math.abs(size[1] - size[2]) < 0.05 && size[0] < 0.16;
	if (e.tris < 150 || Math.max(...size) < 0.5 || wheel) return 0;
	return e.tris > 400 && c[2] > 0.4 ? 2 : 1; // the front cowl takes most hits: twice
}

// One midpoint-subdivision pass over `tris` (triangle indices into the attribute arrays).
function subdivide(attrs, tris) {
	const mid = new Map();
	const out = [];
	const midpoint = (a, b) => {
		const k = a < b ? `${a}_${b}` : `${b}_${a}`;
		if (mid.has(k)) return mid.get(k);
		const id = attrs.count++;
		for (const [name, arr] of Object.entries(attrs.data)) {
			const w = attrs.width[name];
			for (let i = 0; i < w; i++) arr.push((arr[a * w + i] + arr[b * w + i]) * 0.5);
			if (name === 'NORMAL') {
				const o = id * 3;
				const l = Math.hypot(arr[o], arr[o + 1], arr[o + 2]) || 1;
				arr[o] /= l;
				arr[o + 1] /= l;
				arr[o + 2] /= l;
			}
			if (name === 'TANGENT') arr[id * 4 + 3] = arr[a * 4 + 3];
		}
		mid.set(k, id);
		return id;
	};
	for (let t = 0; t < tris.length; t += 3) {
		const [a, b, c] = [tris[t], tris[t + 1], tris[t + 2]];
		const ab = midpoint(a, b);
		const bc = midpoint(b, c);
		const ca = midpoint(c, a);
		out.push(a, ab, ca, ab, b, bc, ca, bc, c, ab, bc, ca);
	}
	return out;
}

const report = { parts: {}, tris: {} };
for (const mesh of doc.getRoot().listMeshes()) {
	const s = nodeScale(mesh);
	for (const prim of mesh.listPrimitives()) {
		const isGlass = !prim.getMaterial() || !prim.getMaterial().getBaseColorTexture();
		const names = prim.listSemantics().filter((n) => !n.startsWith('TEXCOORD_1'));
		const attrs = { data: {}, width: {}, count: prim.getAttribute('POSITION').getCount() };
		for (const n of names) {
			const acc = prim.getAttribute(n);
			attrs.data[n] = Array.from(acc.getArray());
			attrs.width[n] = acc.getElementSize();
		}
		const idxAcc = prim.getIndices();
		let idx = idxAcc ? Array.from(idxAcc.getArray()) : [...Array(attrs.count).keys()];
		const { vc, info } = components(Float32Array.from(attrs.data.POSITION), idx);
		const partOf = new Map();
		for (const [c, e] of info) {
			const p = classify(isGlass, e, s);
			partOf.set(c, p);
			report.parts[p] = (report.parts[p] || 0) + 1;
		}
		// Vertex part ids (before subdivision, so midpoints inherit them through interpolation:
		// a midpoint of two same-part vertices has that same id).
		const part = new Array(attrs.count);
		for (let v = 0; v < attrs.count; v++) part[v] = partOf.get(vc[v]) ?? PART.BODY;
		attrs.data.PARTID = part.map((p) => [p, 0]).flat();
		attrs.width.PARTID = 2;
		if (!isGlass) {
			// Group triangles by subdivision level, subdivide each group, keep the rest.
			const groups = new Map();
			for (let t = 0; t < idx.length; t += 3) {
				const lv = subdivLevels(info.get(vc[idx[t]]), s);
				if (!groups.has(lv)) groups.set(lv, []);
				groups.get(lv).push(idx[t], idx[t + 1], idx[t + 2]);
			}
			idx = [];
			for (const [lv, tris] of groups) {
				let cur = tris;
				for (let i = 0; i < lv; i++) cur = subdivide(attrs, cur);
				idx.push(...cur);
			}
		}
		const buffer = doc.getRoot().listBuffers()[0];
		for (const n of names) {
			const acc = prim.getAttribute(n);
			acc.setArray(new Float32Array(attrs.data[n]));
		}
		const uv2 = doc.createAccessor(`part_ids_${mesh.getName()}`).setType('VEC2')
			.setArray(new Float32Array(attrs.data.PARTID)).setBuffer(buffer);
		prim.setAttribute('TEXCOORD_1', uv2);
		prim.setIndices(doc.createAccessor().setType('SCALAR').setArray(new Uint32Array(idx)).setBuffer(buffer));
		report.tris[mesh.getName()] = idx.length / 3;
	}
}
// keepAttributes: no material samples UV2, and prune would strip the part ids as "unused".
await doc.transform(prune({ keepAttributes: true }));
await io.write(out, doc);
console.log(JSON.stringify(report));
