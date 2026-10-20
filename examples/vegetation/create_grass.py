"""Build an original, static grass study with Blender (no game assets required).

blender --background --factory-startup --python create_grass.py -- --output DIR
Writes editable .blend, a PNG texture, three-LOD MLOD P3D, and addon config.
The small MLOD writer is specific to this generated mesh, not a general exporter.
"""
import argparse
import math
from pathlib import Path
import random
import struct
import sys

import bpy
from mathutils import Vector


def fixed(text, size):
    data = text.encode("ascii")
    if len(data) >= size:
        raise ValueError(f"Field exceeds {size - 1} bytes: {text}")
    return data.ljust(size, b"\0")


def write_model(path, objects):
    with path.open("wb") as stream:
        stream.write(b"MLOD" + struct.pack("<BBHI", 1, 1, 0, len(objects)))
        for obj in objects:
            mesh = obj.data
            mesh.calc_loop_triangles()
            triangles = list(mesh.loop_triangles)
            stream.write(b"SP3X" + struct.pack("<6i", 28, 1, len(mesh.vertices), len(triangles), len(triangles), 0))
            for vertex in mesh.vertices:
                x, y, z = vertex.co
                stream.write(struct.pack("<3fi", x, z, y, 0))
            for triangle in triangles:
                x, y, z = triangle.normal
                stream.write(struct.pack("<3f", x, z, y))
            for index, triangle in enumerate(triangles):
                stream.write(fixed("nvl_grass\\grass.paa", 32) + struct.pack("<i", 3))
                for vertex, loop in zip(triangle.vertices, triangle.loops):
                    u, v = mesh.uv_layers.active.data[loop].uv
                    stream.write(struct.pack("<2i2f", vertex, index, u, 1 - v))
                stream.write(struct.pack("<2i2f", 0, 0, 0, 0))
                stream.write(struct.pack("<i", 0x20))  # BothSidesLight
            stream.write(b"TAGG")
            for name, value in (("autocenter", "0"), ("class", "plant"), ("map", "hide")):
                payload = fixed(name, 64) + fixed(value, 64)
                stream.write(fixed("#Property#", 64) + struct.pack("<i", len(payload)) + payload)
            stream.write(fixed("#EndOfFile#", 64) + struct.pack("<if", 0, obj["cwr_lod_resolution"]))


def grass_mesh(name, blades, resolution, material):
    rng = random.Random(7821)
    vertices, faces, face_uvs = [], [], []
    for blade in range(blades):
        angle = rng.uniform(0, math.tau)
        radius = math.sqrt(rng.random()) * 0.34
        base = Vector((radius * math.cos(angle), radius * math.sin(angle), 0))
        lean_angle = angle + rng.uniform(-0.7, 0.7)
        lean = Vector((math.cos(lean_angle), math.sin(lean_angle), 0))
        across = Vector((-lean.y, lean.x, 0))
        height = rng.uniform(0.32, 0.77) * (1 - radius * 0.4)
        width = rng.uniform(0.018, 0.045)
        bend = rng.uniform(0.12, 0.36)
        stripe = rng.randrange(16)
        start = len(vertices)
        for step in range(4):
            t = step / 4
            center = base + lean * (bend * t * t) + Vector((0, 0, height * t))
            half_width = width * (1 - t * 0.8) * 0.5
            vertices.extend([center - across * half_width, center + across * half_width])
        tip = base + lean * bend + Vector((0, 0, height))
        vertices.append(tip)
        left, right = (stripe + 0.15) / 16, (stripe + 0.85) / 16
        for step in range(3):
            i = start + step * 2
            faces.append((i, i + 1, i + 3, i + 2))
            face_uvs.append(((left, step / 4), (right, step / 4), (right, (step + 1) / 4), (left, (step + 1) / 4)))
        faces.append((start + 6, start + 7, start + 8))
        face_uvs.append(((left, 0.75), (right, 0.75), ((left + right) / 2, 1)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    uv = mesh.uv_layers.new(name="UVMap")
    for poly, coordinates in zip(mesh.polygons, face_uvs):
        for loop, value in zip(poly.loop_indices, coordinates):
            uv.data[loop].uv = value
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    obj["cwr_lod_resolution"] = resolution
    return obj


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--render", action="store_true")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
output = args.output.resolve()
source = output / "source" / "nvl_grass"
source.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

image = bpy.data.images.new("Meadow blade colours", width=256, height=256, alpha=True)
pixels = []
for y in range(256):
    t = y / 255
    for x in range(256):
        variation = random.Random(x // 16 + 41).uniform(0.8, 1.2)
        vein = 1 - 0.10 * abs((x % 16) - 7.5) / 7.5
        pixels.extend(((0.055 + 0.15 * t) * variation * vein,
                       (0.095 + 0.17 * t) * variation * vein,
                       (0.018 + 0.045 * t) * variation * vein, 1))
image.pixels.foreach_set(pixels)
image.filepath_raw = str(output / "grass.png")
image.file_format = "PNG"
image.save()
image.pack()
material = bpy.data.materials.new("Meadow greens")
material.use_nodes = True
material.diffuse_color = (0.22, 0.33, 0.10, 1)
material.use_backface_culling = False
nodes = material.node_tree.nodes
texture = nodes.new("ShaderNodeTexImage")
texture.image = image
shader = nodes.get("Principled BSDF")
shader.inputs["Roughness"].default_value = 0.9
material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
lods = [grass_mesh(f"Grass LOD {distance}", count, distance, material)
        for count, distance in ((72, 1.0), (24, 5.0), (8, 12.0))]
write_model(source / "grass.p3d", lods)
for obj in lods[1:]:
    obj.hide_render = True
    obj.hide_set(True)
bpy.context.view_layer.objects.active = lods[0]
lods[0].select_set(True)

(source / "config.cpp").write_text(r'''class CfgPatches
{
    class NVL_GrassStudy
    {
        units[] = {"NVL_GrassStudy"};
        weapons[] = {};
        requiredVersion = 1.99;
    };
};
class CfgVehicles
{
    class Thing {};
    class NVL_GrassStudy : Thing
    {
        scope = 2;
        displayName = "Meadow grass study";
        model = "\nvl_grass\grass.p3d";
        armor = 1;
        destrType = "DestructNo";
        simulation = "thing";
    };
};
''')
bpy.ops.wm.save_as_mainfile(filepath=str(output / "grass-study.blend"))
print("CREATED_GRASS_STUDY", source, "triangles", [len(obj.data.loop_triangles) for obj in lods])

if args.render:
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.005))
    ground = bpy.context.object
    mat = bpy.data.materials.new("Warm ground")
    mat.diffuse_color = (0.13, 0.12, 0.08, 1)
    ground.data.materials.append(mat)
    bpy.ops.object.camera_add(location=(1.3, -1.6, 1.05))
    camera = bpy.context.object
    camera.rotation_euler = (Vector((0, 0, 0.32)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 1.5
    bpy.context.scene.camera = camera
    bpy.ops.object.light_add(type="AREA", location=(-2, -2, 4))
    bpy.context.object.data.energy = 450
    bpy.context.object.data.size = 4
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
    scene.world.color = (0.35, 0.35, 0.35)
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.filepath = str(output / "grass-study.png")
    bpy.ops.render.render(write_still=True)
