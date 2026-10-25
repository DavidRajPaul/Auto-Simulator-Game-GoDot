// Turns an animated/skinned model into a static prop: removes animations, skins and the
// joint/weight attributes. Used for traffic models that never move their own limbs (the cow).
// Usage: node static_prop.mjs <input> <output>
import { NodeIO } from '@gltf-transform/core';
import { prune } from '@gltf-transform/functions';

const [, , input, output] = process.argv;
const io = new NodeIO();
const doc = await io.read(input);
for (const anim of doc.getRoot().listAnimations()) anim.dispose();
for (const mesh of doc.getRoot().listMeshes()) {
	for (const prim of mesh.listPrimitives()) {
		for (const sem of prim.listSemantics()) {
			if (sem.startsWith('JOINTS_') || sem.startsWith('WEIGHTS_')) prim.setAttribute(sem, null);
		}
	}
}
for (const node of doc.getRoot().listNodes()) node.setSkin(null);
for (const skin of doc.getRoot().listSkins()) skin.dispose();
await doc.transform(prune());
await io.write(output, doc);
