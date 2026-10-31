// Welds and simplifies a textured mesh to a triangle budget WITHOUT smearing its texture:
// UV seams are attribute borders after welding, and lockBorder keeps them fixed (only interior
// vertices of each UV island collapse). Keeps the base colour texture, matte finish.
// Usage: node seam_safe_simplify.mjs <input.glb> <output.glb> <triangle budget>
import { NodeIO } from '@gltf-transform/core';
import { weld, simplify, prune, dedup } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';

const [, , input, output, budgetArg] = process.argv;
const budget = Number(budgetArg || 7000);
const io = new NodeIO();
const doc = await io.read(input);
for (const mat of doc.getRoot().listMaterials()) {
	mat.setMetallicFactor(0.0);
	mat.setRoughnessFactor(0.8);
}
const count = () => {
	let n = 0;
	for (const mesh of doc.getRoot().listMeshes()) {
		for (const prim of mesh.listPrimitives()) n += prim.getIndices().getCount() / 3;
	}
	return n;
};
await MeshoptSimplifier.ready;
await doc.transform(weld(), dedup());
const before = count();
if (before > budget) {
	await doc.transform(simplify({ simplifier: MeshoptSimplifier, ratio: budget / before, error: 0.01, lockBorder: true }));
}
await doc.transform(prune());
await io.write(output, doc);
console.log(`seam_safe_simplify: ${Math.round(before)} -> ${Math.round(count())} triangles`);
