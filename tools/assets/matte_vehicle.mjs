// Makes a traffic vehicle mobile-friendly: keeps only the base-colour texture (drops normal,
// metallic-roughness, occlusion and emissive maps), sets a matte non-metal finish so it never
// renders black without reflection probes, then welds and simplifies to a triangle budget.
// Feed it a palette-textured mesh (process_vehicle_packs.py): a photo/AI texture atlas smears
// across UV seams when simplified.
// Usage: node matte_vehicle.mjs <input.glb> <output.glb> <triangle budget>
import { NodeIO } from '@gltf-transform/core';
import { weld, simplify, prune, dedup } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';

const [, , input, output, budgetArg] = process.argv;
const budget = Number(budgetArg || 3000);
const io = new NodeIO();
const doc = await io.read(input);

for (const mat of doc.getRoot().listMaterials()) {
	mat.setNormalTexture(null);
	mat.setMetallicRoughnessTexture(null);
	mat.setOcclusionTexture(null);
	mat.setEmissiveTexture(null);
	mat.setMetallicFactor(0.0);
	mat.setRoughnessFactor(0.65);
}

let tris = 0;
for (const mesh of doc.getRoot().listMeshes()) {
	for (const prim of mesh.listPrimitives()) {
		const idx = prim.getIndices();
		tris += (idx ? idx.getCount() : prim.getAttribute('POSITION').getCount()) / 3;
	}
}
await MeshoptSimplifier.ready;
await doc.transform(weld(), dedup());
if (tris > budget) {
	await doc.transform(simplify({ simplifier: MeshoptSimplifier, ratio: budget / tris, error: 0.04, lockBorder: false }));
}
await doc.transform(prune());
await io.write(output, doc);

let after = 0;
for (const mesh of doc.getRoot().listMeshes()) {
	for (const prim of mesh.listPrimitives()) after += prim.getIndices().getCount() / 3;
}
console.log(`matte_vehicle: ${Math.round(tris)} -> ${Math.round(after)} triangles`);
