"""Shared writer for story quests: Python values -> Godot text resources.

Used by tools/quests/build_sq*_story.py. Each builder describes its stages, cast, props, cutscenes
and barks in Python and calls write_story() + write_mission() to produce
data/missions/stories/sq_NNN_story.tres and data/missions/side_quests/sq_NNN.tres.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PEOPLE = "res://assets/models/people/"


class V3(tuple):
    pass


class V2(tuple):
    pass


class Col(tuple):
    pass


class PSA(list):
    pass


NONE = Col((0.0, 0.0, 0.0, 0.0))


def num(x):
    if isinstance(x, bool):
        raise TypeError(x)
    if isinstance(x, int):
        return str(x)
    return repr(float(x))


def g(v):
    """Python value -> Godot text resource variant."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, V3):
        return "Vector3(%s, %s, %s)" % tuple(num(x) for x in v)
    if isinstance(v, V2):
        return "Vector2(%s, %s)" % tuple(num(x) for x in v)
    if isinstance(v, Col):
        return "Color(%s, %s, %s, %s)" % tuple(num(x) for x in v)
    if isinstance(v, PSA):
        return "PackedStringArray(%s)" % ", ".join('"%s"' % x for x in v)
    if isinstance(v, (int, float)):
        return num(v)
    if isinstance(v, str):
        return '"%s"' % v.replace("\\", "\\\\").replace('"', '\\"')
    if isinstance(v, dict):
        if not v:
            return "{}"
        return "{\n" + ",\n".join('"%s": %s' % (k, g(x)) for k, x in v.items()) + "\n}"
    if isinstance(v, (list, tuple)):
        return "[" + ", ".join(g(x) for x in v) + "]"
    raise TypeError(v)


def write_story(quest_id, voice_dir, speakers, cast, props, cutscenes, barks):
    story = ['[gd_resource type="Resource" script_class="QuestStoryData" load_steps=2 format=3]',
             '[ext_resource type="Script" path="res://data/missions/QuestStoryData.gd" id="story"]',
             '[resource]', 'script = ExtResource("story")',
             'voice_dir = "%s"' % voice_dir,
             'speakers = ' + g(speakers), 'cast = ' + g(cast), 'props = ' + g(props),
             'cutscenes = ' + g(cutscenes), 'barks = ' + g(barks)]
    out = ROOT / f"data/missions/stories/{quest_id}_story.tres"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(story) + "\n", encoding="utf-8")


ORDER = ["id", "kind", "objective_key", "target", "radius_m", "arrival_speed_kmh", "duration_s", "choices", "next_by_choice",
         "quality_key", "place_key", "place_pos", "cutscene_id", "spot_pos", "spot_range_m", "spot_max_kmh", "shrink_after_s",
         "shrink_radius_m", "next_id"]


def write_mission(quest_id, stages, fields):
    """fields: (name, value) pairs for the MissionDef after id, in file order; values go through g()
    unless they are already Godot text (str starting with 'ExtResource')."""
    lines = ['[gd_resource type="Resource" script_class="MissionDef" load_steps=%d format=3]' % (len(stages) + 4),
             '[ext_resource type="Script" path="res://data/missions/MissionDef.gd" id="def"]',
             '[ext_resource type="Script" path="res://data/missions/MissionStage.gd" id="stage"]',
             f'[ext_resource type="Resource" path="res://data/missions/stories/{quest_id}_story.tres" id="story"]']
    for st in stages:
        lines.append('[sub_resource type="Resource" id="%s"]' % st["id"])
        lines.append('script = ExtResource("stage")')
        for k in ORDER:
            if k in st:
                lines.append("%s = %s" % (k, g(st[k])))
    lines += ['[resource]', 'script = ExtResource("def")', 'id = "%s"' % quest_id]
    for name, value in fields:
        lines.append("%s = %s" % (name, value if isinstance(value, str) and value.startswith("ExtResource") else g(value)))
    lines.append('story = ExtResource("story")')
    lines.append('stages = Array[ExtResource("stage")]([%s])' % ", ".join('SubResource("%s")' % s["id"] for s in stages))
    (ROOT / f"data/missions/side_quests/{quest_id}.tres").write_text("\n".join(lines) + "\n", encoding="utf-8")
