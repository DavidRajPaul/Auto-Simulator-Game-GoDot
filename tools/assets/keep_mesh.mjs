// Keeps only the nodes whose mesh name contains <match> and drops the rest (some downloads ship
// two animals in one file). The kept node is moved to the origin so the fit code sees one body.
// Usage: node keep_mesh.mjs <input> <output> <match>
import { NodeIO } from '@gltf-transform/core';
import { prune } from '@gltf-transform/functions';

const [, , input, output, match] = process.argv;
const io = new NodeIO();
const doc = await io.read(input);
let kept = 0;
for (const node of doc.getRoot().listNodes()) {
	const mesh = node.getMesh();
	if (!mesh) continue;
	if (mesh.getName().includes(match)) {
		kept++;
		const t = node.getTranslation();
		node.setTranslation([0, t[1], 0]);
	} else {
		node.dispose();
	}
}
if (kept === 0) throw new Error(`no mesh matched "${match}"`);
await doc.transform(prune());
await io.write(output, doc);
