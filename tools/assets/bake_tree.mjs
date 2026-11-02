// One street-tree source GLB (owner's Tripo model, unit size) -> the real-size game model.
// Called by tools/assets/bake_trees.py; prints a JSON line with the baked size.
//
// Scales to `height` metres, moves the trunk base (centre of the lowest 2 % of vertices) to the
// origin, makes the material matte and non-metal (glTF defaults metallic to 1.0, which renders
// near-black on mobile), welds. No simplification: every leaf card is its own UV island, so
// meshoptimizer either stalls (locked borders) or shreds the cards (free borders). Distance
// detail comes from the impostor atlas instead.
//
// Usage: node bake_tree.mjs <src.glb> <out.glb> <height m>
import { NodeIO } from '@gltf-transform/core';
import { weld, prune, dedup } from '@gltf-transform/functions';

const [, , src, out, heightArg] = process.argv;
const height = Number(heightArg);
const io = new NodeIO();
const doc = await io.read(src);

const prims = doc.getRoot().listMeshes().flatMap((m) => m.listPrimitives());
if (prims.length !== 1) throw new Error(`${src}: expected 1 primitive, found ${prims.length}`);
for (const node of doc.getRoot().listNodes()) {
	node.setTranslation([0, 0, 0]).setRotation([0, 0, 0, 1]).setScale([1, 1, 1]);
}
for (const mat of doc.getRoot().listMaterials()) {
	mat.setMetallicFactor(0.0);
	mat.setRoughnessFactor(1.0);
	mat.setDoubleSided(true);
	mat.setAlphaMode('OPAQUE');
}

const pos = prims[0].getAttribute('POSITION');
const n = pos.getCount();
const p = [0, 0, 0];
let minY = Infinity;
let maxY = -Infinity;
for (let i = 0; i < n; i++) {
	pos.getElement(i, p);
	minY = Math.min(minY, p[1]);
	maxY = Math.max(maxY, p[1]);
}
const cut = minY + (maxY - minY) * 0.02;
let bx = 0;
let bz = 0;
let bn = 0;
for (let i = 0; i < n; i++) {
	pos.getElement(i, p);
	if (p[1] <= cut) {
		bx += p[0];
		bz += p[2];
		bn++;
	}
}
bx /= bn;
bz /= bn;
const s = height / (maxY - minY);
let radius = 0;
for (let i = 0; i < n; i++) {
	pos.getElement(i, p);
	const q = [(p[0] - bx) * s, (p[1] - minY) * s, (p[2] - bz) * s];
	radius = Math.max(radius, Math.hypot(q[0], q[2]));
	pos.setElement(i, q);
}

await doc.transform(weld(), dedup(), prune());
await io.write(out, doc);
const tris = doc.getRoot().listMeshes().flatMap((m) => m.listPrimitives())
	.reduce((t, pr) => t + (pr.getIndices() ? pr.getIndices().getCount() : pr.getAttribute('POSITION').getCount()) / 3, 0);
console.log(JSON.stringify({ height, radius: Math.round(radius * 100) / 100, tris }));
