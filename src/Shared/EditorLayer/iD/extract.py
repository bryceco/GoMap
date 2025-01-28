#!/usr/bin/env python

import argparse
import os
import regex
import sys


parser = argparse.ArgumentParser(description="Convert CSS files to a Swift theme file.")
parser.add_argument("input_dir", help="Input directory containing .css files")
parser.add_argument(
    "-o",
    "--output",
    default="./Theme.swift",
    help="Output Swift theme file path (default: ./Theme.swift)",
)
parser.add_argument(
    "--debug", action="store_true", help="generate code with timing information"
)
parser.add_argument(
    "--decomp",
    action="store_true",
    help="generate standalone code paste-able into godbolt.org",
)
args = parser.parse_args()

# Read all .css files in the input directory
css_files = [
    os.path.join(args.input_dir, f)
    for f in os.listdir(args.input_dir)
    if f.endswith(".css")
]

skip = ["path.area.fill", "path.area.stroke"]

regex_escape = regex.compile(r'"|\\|\p{C}|[^ \P{Z}]')


def swift_repr(s):
    return (
        '"'
        + regex_escape.sub(
            lambda c: {
                "\x00": "\\0",
                "\\": "\\\\",
                "\t": "\\t",
                "\n": "\\n",
                "\r": "\\r",
                '"': '\\"',
            }.get(c, f"\\u{{{ord(c):x}}}"),
            s,
        )
        + '"'
    )


indent_start = 2

render_keys = [
    "and",
    "not",
    "lineColor",
    "lineOpacity",
    "lineWidth",
    "lineCap",
    "lineDashPattern",
    "casingColor",
    "casingOpacity",
    "casingWidth",
    "casingCap",
    "casingDashPattern",
    "areaColor",
]

primaries = [
    "building",
    "highway",
    "railway",
    "waterway",
    "aeroway",
    "aerialway",
    "piste:type",
    "boundary",
    "power",
    "amenity",
    "natural",
    "landuse",
    "leisure",
    "military",
    "place",
    "man_made",
    "route",
    "attraction",
    "roller_coaster",
    "building:part",
    "indoor",
]
statuses = [
    "proposed",
    "planned",
    "construction",
    "disused",
    "abandoned",
    "was",
    "dismantled",
    "razed",
    "demolished",
    "destroyed",
    "removed",
    "obliterated",
    "intermittent",
]
secondaries = [
    "oneway",
    "bridge",
    "tunnel",
    "embankment",
    "cutting",
    "barrier",
    "surface",
    "tracktype",
    "footway",
    "crossing",
    "service",
    "sport",
    "public_transport",
    "location",
    "parking",
    "golf",
    "type",
    "leisure",
    "man_made",
    "indoor",
    "construction",
    "proposed",
]

surfaces = ["paved", "unpaved", "semipaved"]


# TODO: also check key != primary
def has_tag(key, value, cmp="=="):
    if value is None:
        if cmp == "==":
            return f"has(tags, {swift_repr(key)})"
        else:
            return f"!has(tags, {swift_repr(key)})"
    return f"tags[{swift_repr(key)}] {cmp} {swift_repr(value)}"


def selector_to_if(selector, cmp="=="):
    if "-" in selector:
        key, value = selector.split("-", 1)
    else:
        key = selector
        value = None

    if key == "piste":
        key = "piste:type"
    if key == "building_part":
        key = "building:part"

    if key in primaries:
        if cmp == "==":
            if value is None:
                cond = f"primary {cmp} {swift_repr(key)}"
            else:
                cond = f"(primary {cmp} {swift_repr(key)} && primaryValue {cmp} {swift_repr(value)})"
            if key in secondaries:  # some are both
                cond = "(" + cond + " || " + has_tag(key, value, cmp) + ")"
        else:
            if value is None:
                cond = f"primary {cmp} {swift_repr(key)}"
            else:
                cond = f"primary == {swift_repr(key)} && primaryValue {cmp} {swift_repr(value)}"
            if key in secondaries:  # some are both
                cond = "(" + cond + " && " + has_tag(key, value, cmp) + ")"
        return cond

    if key == "status":
        if value is None:
            if cmp == "==":
                return "status != nil"
            return "status == nil"
        return f"status {cmp} {swift_repr(value)}"

    if selector in surfaces:
        return f"surface {cmp} {swift_repr(selector)}"

    return has_tag(key, value, cmp)


def to_swift_fn(styles, indent=0):
    res = 'let r = RenderInfo(key: primary ?? "", value: primaryValue)\n'
    for keys, style in styles:
        if_stms = []
        for [selector, and_styles, not_styles] in keys:
            if_stm = selector_to_if(selector)
            for and_selector in sorted(and_styles):  # sort to help branch predictor
                if_stm += " && " + selector_to_if(and_selector)
            for not_selector in sorted(not_styles):
                if_stm += " && " + selector_to_if(not_selector, "!=")
            if_stms.append(if_stm)
        if len(if_stms) > 1:
            if_stms = ["(" + if_stm + ")" for if_stm in if_stms]
            rendered_if = " || ".join(if_stms)
        else:
            rendered_if = if_stms[0]
        res += "\t" * indent + "if " + rendered_if + " {\n"
        res += to_swift(style, indent + 1)
        res += "\t" * indent + "}" + "\n"
    return res


def to_swift(obj, indent=indent_start):
    if isinstance(obj, dict):
        res = ""
        for k in render_keys:
            if k not in obj:
                continue
            v = obj[k]
            res += "\t" * indent
            if k.endswith("Color"):
                color_keys = ["red", "green", "blue", "alpha"]
                if len(v) == 3:
                    v.append(1.0)
                r, g, b, a = v
                r, g, b = [
                    f"{color_val / 255.0:.3f}".rstrip("0") for color_val in [r, g, b]
                ]
                r, g, b = [
                    color_val + "0" if color_val.endswith(".") else color_val
                    for color_val in [r, g, b]
                ]

                res += (
                    f"r.{k} = DynamicColor("
                    + ", ".join(
                        f"{color_key}: {color_val}"
                        for color_key, color_val in zip(color_keys, [r, g, b, a])
                    )
                    + ")"
                )
            elif k.endswith("Cap"):
                res += f"r.{k} = .{v}"
            else:
                res += f"r.{k} = {to_swift(v, indent+1)}"
            res += "\n"
        return res
    if isinstance(obj, list):
        return "[" + ", ".join(to_swift(v, indent + 1) for v in obj) + "]"
    if isinstance(obj, str):
        return swift_repr(obj)
    if obj is None:
        return "nil"
    if isinstance(obj, bool):
        return "true" if obj else "false"
    if isinstance(obj, (int, float)):
        return str(obj)
    raise ValueError(obj)


def err(*args, **kwargs):
    print(*args, **kwargs, file=sys.stderr)


def extract_path_css(file_path):
    with open(file_path, "r") as file:
        lines = file.readlines()

    path_css = []
    inside_path = False
    current_group = []

    for line in lines:
        line = line.strip()
        if line.startswith("path.") and not inside_path:
            inside_path = True
            current_group.append(line)
        elif inside_path:
            current_group.append(line)
            if line == "}":
                inside_path = False
                path_css.append(" ".join(current_group))
                current_group = []

    return path_css


styles = []
seen_keys = []
css_keys = {
    "stroke": 126,
    "stroke-width": 58,
    "stroke-dasharray": 33,
    "stroke-linecap": 28,
    "fill": 16,
    "stroke-opacity": 4,
    "fill-rule": 1,
    "visibility": 1,
}


def parse_css_color(value):
    if value.startswith("#"):
        value = value.removeprefix("#")
        if len(value) == 3:
            return [int(c * 2, 16) for c in value]
        elif len(value) == 6:
            return [int(value[i : i + 2], 16) for i in range(0, 6, 2)]
        else:
            err("Error parsing color:", value)
    elif value.startswith("rgb("):
        value = value.removeprefix("rgb(").removesuffix(")")
        return [int(c) for c in value.split(",")]
    elif value.startswith("rgba("):
        value = value.removeprefix("rgba(").removesuffix(")")
        r, g, b, a = [n.strip() for n in value.split(",")]
        return [int(r), int(g), int(b), float(a)]
    elif value == "white":
        return [255, 255, 255, 1.0]
    elif value == "none":
        return None
    else:
        err("Error parsing color:", value)


def parse_css_width(value):
    return float(value.removesuffix("px"))


def int_or_float(n):
    n = float(n) / 2
    if int(n) == n:
        return int(n)
    return n


for file_path in sorted(css_files):
    path_css = extract_path_css(file_path)
    for group in path_css:
        classes, css = group.split("{", 1)
        classes = [c.strip() for c in classes.strip().split(",")]
        css = css.strip().removesuffix("}")
        css = [l.strip() for l in css.split(";") if l.strip()]
        json_css = {}
        for l in css:
            key, value = l.split(":", 1)
            value = value.replace("!important", "").strip()
            if key not in css_keys:
                err("Error, key not in css_keys:", key, value)
                continue

            if key == "stroke":
                color = parse_css_color(value)
                if color is not None:
                    json_css["lineColor"] = color
            if key == "stroke-opacity":
                json_css["lineOpacity"] = float(value)
            if key == "stroke-width":
                json_css["lineWidth"] = parse_css_width(value) / 2
            if key == "stroke-linecap":
                json_css["lineCap"] = value
            if key == "stroke-dasharray":
                if value == "none":
                    json_css["lineDashPattern"] = None
                else:
                    value = value.split(",")
                    json_css["lineDashPattern"] = [
                        int_or_float(v.removesuffix("px")) for v in value
                    ]
        # err(css)
        # err(json_css)
        # err()

        for c in classes:
            if c == "path.line.stroke.tag-service.tag-service":
                c = "path.line.stroke.tag-service"

            if c in skip:
                continue
            no_not = c
            not_parts = []
            if ":not(" in c:
                no_not, *not_parts = c.split(":not(")
                not_parts = [
                    p.removeprefix(".tag-").removesuffix(")") for p in not_parts
                ]

            parts = no_not.split(".")
            if parts[0] != "path":
                continue
            if len(parts) < 3:
                err("Error, not enough selector parts:", c)
                continue

            subtypes = ["casing", "fill", "shadow", "stroke"]
            type_, *rest = parts[1:]
            subtype = None
            if type_ not in ("line", "area"):
                if type_ not in subtypes:
                    err("Error, type not one of the known subtypes:", c)
                    continue
                else:
                    subtype = type_
                    type_ = None
            else:
                [subtype, *rest] = rest
                if subtype not in subtypes:
                    err("Error, subtype not one of the known subtypes:", c)
                    continue

            if subtype == "shadow":
                # TODO: shadows?
                # err('SKIP', c)
                continue

            if len(list(dict.fromkeys(rest))) != len(rest):
                err("Error: repeated selector parts:", c)
                continue
            rest = list(dict.fromkeys(rest))  # remove duplicates
            if len(rest) == 0:
                err("Error, no tag in selector:", c)
                continue

            if not all(r.startswith("tag-") for r in rest):
                # err('SKIP', c, r)
                continue
            rest = [r.removeprefix("tag-") for r in rest]
            if any(r.count("-") > 1 for r in rest):
                err("Error, multiple dashes in class:", c)
                continue

            key, *and_parts = rest

            # if there's not '-' that's fine, it will apply to any value for that key
            new_styles = {**json_css}
            if subtype == "fill":
                if "lineColor" in json_css:
                    new_styles["areaColor"] = json_css["lineColor"]
                    del new_styles["lineColor"]
            if subtype == "casing":
                if "lineColor" in json_css:
                    new_styles["casingColor"] = json_css["lineColor"]
                    del new_styles["lineColor"]
                if "lineOpacity" in json_css:
                    new_styles["casingOpacity"] = json_css["lineOpacity"]
                    del new_styles["lineOpacity"]
                if "lineWidth" in json_css:
                    new_styles["casingWidth"] = json_css["lineWidth"]
                    del new_styles["lineWidth"]
                if "lineCap" in json_css:
                    new_styles["casingCap"] = json_css["lineCap"]
                    del new_styles["lineCap"]
                if "lineDashPattern" in json_css:
                    new_styles["casingDashPattern"] = json_css["lineDashPattern"]
                    del new_styles["lineDashPattern"]

            if new_styles:
                styles.append([[key, and_parts, not_parts], new_styles])

            # err(c, css)
        # err(classes, css)


# https://www.w3.org/TR/CSS21/cascade.html#specificity
def css_precedence(style):
    return 1 + len(style[1]) + len(style[2])


def css_keys_equal(a, b):
    if isinstance(a[0], list):
        return len(a) == len(b) and all(
            css_keys_equal(a[i], b[i]) for i in range(len(a))
        )
    return (
        a[0] == b[0] and sorted(a[1]) == sorted(b[1]) and sorted(a[2]) == sorted(b[2])
    )


def merge_styles(styles):
    new_styles = []
    # if it's the same as the previous selector and they don't set conflicting properties, merge the styles
    for i, (key, style) in enumerate(styles):
        if i == 0:
            new_styles.append((key, style))
            continue
        prev_key, prev_style = new_styles[-1]
        if css_keys_equal(key, prev_key):
            shared_keys = style.keys() & prev_style.keys()
            if all(style[k] == prev_style[k] for k in shared_keys):
                new_styles[-1] = (key, {**prev_style, **style})
            else:
                new_styles.append((key, style))
        else:
            new_styles.append((key, style))

    return new_styles


# if the css body is the same, merge the selectors into a list that will
# be checked in order with ||
def merge_styles_part_two(styles):
    new_styles = []
    for i, (key, style) in enumerate(styles):
        if i == 0:
            new_styles.append(([key], style))
            continue
        prev_key, prev_style = new_styles[-1]
        if style == prev_style:
            new_styles[-1] = (prev_key + [key], prev_style)
        else:
            new_styles.append(([key], style))

    return new_styles


styles = merge_styles(styles)
styles = sorted(styles, key=lambda x: css_precedence(x[0]))
styles = merge_styles(styles)
styles = merge_styles_part_two(styles)
styles = merge_styles(styles)

# for k, v in styles:
#     if "-" in k:
#         base = k.split("-")[0]
#         if base in styles:
#             styles[k] = styles[base] | v

debug_start = ""
debug_end = ""
if args.debug:
    debug_start = "let start = Date()\n\t\t"
    debug_end = (
        "\n\t\tlet total = Date().timeIntervalSince(start) * 1000\n"
        + '\t\tprint(String(format: "match   : %.6f ms", total))\n'
    )

decomp = """import Foundation

struct DynamicColor {
    var red: Float
    var green: Float
    var blue: Float
    var alpha: Float

    static let black = DynamicColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let clear = DynamicColor(red: 0, green: 0, blue: 0, alpha: 0)
}
enum LineCapStyle {
    case butt
    case round
    case square
}

class RenderInfo {
    var value: String?
    var lineColor: DynamicColor?
    var lineOpacity: CGFloat = 1.0
    var lineWidth: CGFloat = 0.0
    var lineCap: LineCapStyle = .butt
    var lineDashPattern: [NSNumber]?
    var casingColor: DynamicColor?
    var casingOpacity: CGFloat = 1.0
    var casingWidth: CGFloat = 0.0
    var casingCap: LineCapStyle = .butt
    var casingDashPattern: [NSNumber]?
    var areaColor: DynamicColor?
}

func has(_ tags: [String: String], _ key: String) -> Bool {
    let value = tags[key]
    return value != nil && value != "no"
}
"""

code = """// Copyright (c) 2017, iD Contributors
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
// REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
// AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
// INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
// LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
// OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
// PERFORMANCE OF THIS SOFTWARE.

//
//  Theme.swift
//  Go Map!!
//
//  Created by Boris Verkhovskiy on 2024-03-30.
//

import Foundation
"""
if args.decomp:
    code += decomp
else:
    code += """import UIKit

extension RenderInfo {
\tstatic func has(_ tags: [String: String], _ key: String) -> Bool {
\t\tlet value = tags[key]
\t\treturn value != nil && value != "no"
\t}

\tstatic """

code += "func match(primary: String?, primaryValue: String?, status: String?, surface: String?, tags: [String: String]) -> RenderInfo {\n\t\t"
code += debug_start
code += to_swift_fn(styles, 2)
code += debug_end
code += """
\t\treturn r
\t}
"""
if not args.decomp:
    code += "}"

with open(args.output, "w") as f:
    f.write(code + "\n")
