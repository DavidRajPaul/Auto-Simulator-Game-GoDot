// glTF defaults metallicFactor to 1.0. Models that leave it unset render almost black in Godot
// (no reflections to show), so set plain materials to non-metal and keep their texture as is.
// Materials that already carry a metallic-roughness texture are left alone.
// Usage: node fix_materials.mjs <input> <output>
import { NodeIO } from '@gltf-transform/core';

const [, , input, output] = process.argv;
const io = new NodeIO();
const doc = await io.read(input);
for (const mat of doc.getRoot().listMaterials()) {
	if (mat.getMetallicRoughnessTexture()) continue;
	mat.setMetallicFactor(0.0);
	mat.setRoughnessFactor(Math.max(mat.getRoughnessFactor(), 0.7));
}
await io.write(output, doc);
