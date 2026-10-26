// Removes unwanted parts from a downloaded scene before optimising it as one static landmark:
// nodes whose material name matches any of --drop-mats (comma list, case-insensitive substrings)
// and nodes whose world bounding box is wider than --max-size metres (ground planes, skyboxes).
// Usage: node strip_scene.mjs <input> <output> [--drop-mats a,b] [--max-size 300]
import { NodeIO } from '@gltf-transform/core';
import { getBounds, prune } from '@gltf-transform/functions';

const args = process.argv.slice(2);
const [input, output] = args;
const opt = (name, def) => {
	const i = args.indexOf(name);
	return i >= 0 ? args[i + 1] : def;
};
const dropMats = opt('--drop-mats', '').toLowerCase().split(',').filter((s) => s);
const maxSize = parseFloat(opt('--max-size', '1e9'));
const io = new NodeIO();
const doc = await io.read(input);
let dropped = 0;
for (const node of doc.getRoot().listNodes()) {
	const mesh = node.getMesh();
	if (!mesh) continue;
	const names = mesh.listPrimitives().map((p) => (p.getMaterial()?.getName() ?? '').toLowerCase());
	let drop = names.some((n) => dropMats.some((d) => n.includes(d)));
	if (!drop) {
		const b = getBounds(node);
		const size = Math.max(b.max[0] - b.min[0], b.max[2] - b.min[2]);
		drop = size > maxSize;
	}
	if (drop) {
		node.setMesh(null);
		dropped++;
	}
}
await doc.transform(prune());
await io.write(output, doc);
console.log(`dropped ${dropped} nodes`);
